import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { enforceImageReview, loadImageReview } from './product_image_review.mjs';

const workspace = path.resolve(import.meta.dirname, '..');
const classifiedPath = path.join(
  workspace,
  '.codex_work/product_master/classified_products.json',
);
const customerNamesPath = path.join(
  workspace,
  '.codex_work/product_names/customer_name_mappings.json',
);
const manifestPath = path.join(
  workspace,
  '.codex_work/product_master/product_image_matches.json',
);
const workDirectory = path.join(workspace, '.codex_work/product_images');
const searchCachePath = path.join(workDirectory, 'ddg_search_cache.json');
const rejectedImageUrlsPath = path.join(
  workDirectory,
  'rejected_image_urls.json',
);
const blockedWebImageRowsPath = path.join(
  workDirectory,
  'blocked_web_image_rows.json',
);
const reportPath = path.join(
  workspace,
  'outputs/product_image_import/web_scrape_report.json',
);
const assetDirectory = path.join(workspace, 'assets/product_images/web');

const applyChanges = process.argv.includes('--apply');
const refreshRejected = process.argv.includes('--refresh-rejected');
const refreshScraped = process.argv.includes('--refresh-scraped');
const numberArgument = (flag, fallback) => {
  const index = process.argv.indexOf(flag);
  if (index < 0) return fallback;
  const parsed = Number(process.argv[index + 1]);
  return Number.isFinite(parsed) ? parsed : fallback;
};
const maxQueries = numberArgument('--max-queries', Number.POSITIVE_INFINITY);
const targetCoverage = numberArgument('--target-coverage', 0.6);
const delayMs = numberArgument('--delay-ms', 850);
const minimumScore = numberArgument('--minimum-score', 17);
const cwebpPath = '/opt/homebrew/bin/cwebp';
let rejectedImageUrls = new Set();
let blockedWebImageRows = new Set();

const userAgent = [
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
  'AppleWebKit/537.36 (KHTML, like Gecko)',
  'Chrome/124.0 Safari/537.36',
].join(' ');

const stopWords = new Set([
  'and',
  'by',
  'for',
  'free',
  'from',
  'grocery',
  'india',
  'no',
  'online',
  'pack',
  'packet',
  'pcs',
  'piece',
  'pieces',
  'price',
  'product',
  'set',
  'the',
  'variant',
  'with',
]);
const unitWords = new Set([
  'g',
  'gm',
  'gms',
  'kg',
  'kgs',
  'l',
  'litre',
  'litres',
  'ml',
]);
const lowInformationWords = new Set([
  'care',
  'classic',
  'regular',
  'special',
]);
const productFormWords = new Set([
  'bar',
  'battery',
  'batteries',
  'biscuit',
  'biscuits',
  'blade',
  'blades',
  'coil',
  'conditioner',
  'cream',
  'detergent',
  'gel',
  'ghee',
  'incense',
  'liquid',
  'lotion',
  'masala',
  'mat',
  'oil',
  'powder',
  'razor',
  'sauce',
  'shampoo',
  'soap',
  'spray',
  'sticks',
  'talc',
  'toothpaste',
]);
const rejectedDomains = [
  'facebook.com',
  'instagram.com',
  'pinterest.',
  'storage.googleapis.com',
  'youtube.com',
];
const trustedDomains = new Map([
  ['1mg.com', 4],
  ['amazon.in', 4],
  ['apollopharmacy.in', 4],
  ['bigbasket.com', 7],
  ['blinkit.com', 7],
  ['flipkart.com', 4],
  ['indiamart.com', 3],
  ['jiomart.com', 7],
  ['netmeds.com', 4],
  ['swiggy.com', 7],
  ['zepto.com', 7],
]);

const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));
const toNumber = (value) => {
  const parsed = Number(String(value ?? '').replace(/,/g, '').trim());
  return Number.isFinite(parsed) ? parsed : 0;
};
const normalizeText = (value) =>
  String(value ?? '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/&/g, ' and ')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
const familyName = (value) =>
  String(value ?? '')
    .replace(/\s*\([^)]*(?:₹|Pack|Variant)[^)]*\)/gi, '')
    .replace(/\s*·\s*Variant\s*\d+/gi, '')
    .replace(/\s+/g, ' ')
    .trim();
const tokensFor = (value) =>
  normalizeText(value)
    .split(' ')
    .filter(
      (token) =>
        token.length >= 2 &&
        !stopWords.has(token) &&
        !unitWords.has(token) &&
        !/^\d+$/.test(token),
    );
const unique = (values) => [...new Set(values)];
const hostFor = (value) => {
  try {
    return new URL(value).hostname.replace(/^www\./, '').toLowerCase();
  } catch {
    return '';
  }
};
const domainWeight = (sourceUrl) => {
  const host = hostFor(sourceUrl);
  for (const [domain, weight] of trustedDomains) {
    if (host === domain || host.endsWith(`.${domain}`)) return weight;
  }
  return 0;
};
const measureFor = (value) => {
  const text = normalizeText(value).replace(/\s+/g, '');
  const match = text.match(/(?:^|[^a-z])(\d+(?:\.\d+)?)(kg|kgs|g|gm|gms|ml|l|litre|litres)(?:$|[^a-z])/);
  if (!match) return '';
  const aliases = {
    gm: 'g',
    gms: 'g',
    kgs: 'kg',
    litre: 'l',
    litres: 'l',
  };
  return `${match[1]}${aliases[match[2]] ?? match[2]}`;
};
const sha256 = (value) =>
  crypto.createHash('sha256').update(value).digest('hex');

function scoreCandidate(group, candidate) {
  const combined = `${candidate.title ?? ''} ${candidate.url ?? ''}`;
  const normalized = normalizeText(combined);
  const candidateTokens = new Set(tokensFor(combined));
  const brandTokens = unique(tokensFor(group.brand));
  const nameTokens = unique(
    tokensFor(group.name).filter((token) => !brandTokens.includes(token)),
  );
  const informativeNameTokens = nameTokens.filter(
    (token) => !lowInformationWords.has(token),
  );
  const formTokens = informativeNameTokens.filter((token) =>
    productFormWords.has(token),
  );
  const sharedForm = formTokens.filter((token) => candidateTokens.has(token));
  const sharedBrand = brandTokens.filter((token) => candidateTokens.has(token));
  const sharedName = informativeNameTokens.filter((token) =>
    candidateTokens.has(token),
  );
  const exactBrand =
    !group.brand || normalized.includes(normalizeText(group.brand));
  const brandPass =
    !group.brand ||
    exactBrand ||
    (brandTokens.length > 0 &&
      sharedBrand.length >= Math.min(2, brandTokens.length));
  const requiredNameTokens = group.brand
    ? Math.min(2, Math.max(1, informativeNameTokens.length))
    : Math.min(3, Math.max(2, informativeNameTokens.length));
  const namePass = sharedName.length >= requiredNameTokens;
  const formPass =
    formTokens.length === 0 || sharedForm.length === formTokens.length;
  const sourceHost = hostFor(candidate.url);
  const imageHost = hostFor(candidate.image);
  const rejectedDomain = rejectedDomains.some(
    (domain) => sourceHost.includes(domain) || imageHost.includes(domain),
  );
  const rejectedImage = rejectedImageUrls.has(candidate.image);
  const sourceMeasure = measureFor(group.name);
  const candidateMeasure = measureFor(combined);
  const measureMatch =
    Boolean(sourceMeasure) && sourceMeasure === candidateMeasure;
  const measureMismatch =
    Boolean(sourceMeasure) &&
    Boolean(candidateMeasure) &&
    sourceMeasure !== candidateMeasure;
  const exactName = normalized.includes(normalizeText(group.name));
  const tokenRatio =
    informativeNameTokens.length === 0
      ? 0
      : sharedName.length / informativeNameTokens.length;
  const sourceWeight = domainWeight(candidate.url);
  const aspectRatio =
    candidate.width > 0 && candidate.height > 0
      ? Math.min(candidate.width, candidate.height) /
        Math.max(candidate.width, candidate.height)
      : 0;
  const imageQualityScore =
    (aspectRatio >= 0.78 ? 2 : aspectRatio > 0 && aspectRatio < 0.58 ? -3 : 0) +
    (Math.min(candidate.width, candidate.height) >= 400 ? 1 : 0) -
    (/aplus-media|banner|blog/i.test(candidate.image) ? 8 : 0) -
    (/latest price|dealers|retailers/i.test(candidate.title) ||
    /\/impcat\//i.test(candidate.url)
      ? 5
      : 0) -
    (/\b(?:combo|pack of [2-9])\b/i.test(candidate.title) &&
    !/\b(?:combo|multipack|pack of [2-9])\b/i.test(group.name)
      ? 2
      : 0);
  const score =
    sharedName.length * 4 +
    tokenRatio * 6 +
    sharedBrand.length * 2 +
    (exactBrand && group.brand ? 3 : 0) +
    (exactName ? 7 : 0) +
    (measureMatch ? 5 : 0) +
    sourceWeight +
    imageQualityScore -
    (measureMismatch ? 5 : 0) -
    (rejectedDomain || rejectedImage ? 100 : 0);
  return {
    ...candidate,
    score: Number(score.toFixed(2)),
    brandPass,
    namePass,
    formPass,
    exactBrand,
    exactName,
    sharedBrand,
    sharedName,
    sharedForm,
    sourceMeasure,
    candidateMeasure,
    measureMatch,
    measureMismatch,
    sourceHost,
    sourceWeight,
    aspectRatio: Number(aspectRatio.toFixed(3)),
    imageQualityScore,
    rejectedDomain,
    rejectedImage,
  };
}

function categorySearchHint(category) {
  switch (category) {
    case 'Personal Care':
      return 'personal care toiletry';
    case 'Home Care':
      return 'household cleaning';
    case 'Baby Care':
      return 'baby care';
    case 'Health & Wellness':
      return 'health wellness';
    case 'Pooja & Festive':
      return 'pooja product';
    case 'Beverages':
      return 'beverage';
    case 'Snacks & Sweets':
      return 'snack food';
    case 'Dairy & Frozen':
      return 'dairy food';
    default:
      return 'grocery retail';
  }
}

async function fetchWithRetry(url, options = {}) {
  const retryDelays = [0, 2_500, 7_500, 18_000];
  let lastError;
  for (let attempt = 0; attempt < retryDelays.length; attempt += 1) {
    if (retryDelays[attempt]) await sleep(retryDelays[attempt]);
    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          'Accept-Language': 'en-IN,en;q=0.9',
          'User-Agent': userAgent,
          ...(options.headers ?? {}),
        },
        signal: AbortSignal.timeout(25_000),
      });
      if (response.ok) return response;
      lastError = new Error(`HTTP ${response.status} for ${url}`);
      if (![202, 429, 500, 502, 503, 504].includes(response.status)) break;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? new Error(`Request failed for ${url}`);
}

async function searchImages(query) {
  const searchUrl = new URL('https://duckduckgo.com/');
  searchUrl.searchParams.set('q', query);
  searchUrl.searchParams.set('iax', 'images');
  searchUrl.searchParams.set('ia', 'images');
  const searchResponse = await fetchWithRetry(searchUrl);
  const html = await searchResponse.text();
  const token = html.match(/vqd=["']?([^&"'\s]+)/)?.[1];
  if (!token) throw new Error('DuckDuckGo did not return an image-search token.');

  const imageUrl = new URL('https://duckduckgo.com/i.js');
  imageUrl.searchParams.set('l', 'in-en');
  imageUrl.searchParams.set('o', 'json');
  imageUrl.searchParams.set('q', query);
  imageUrl.searchParams.set('vqd', token);
  imageUrl.searchParams.set('f', ',,,');
  imageUrl.searchParams.set('p', '1');
  const imageResponse = await fetchWithRetry(imageUrl, {
    headers: { Referer: searchUrl.toString() },
  });
  const payload = await imageResponse.json();
  return (payload.results ?? []).slice(0, 100).map((candidate) => ({
    title: candidate.title ?? '',
    url: candidate.url ?? '',
    image: candidate.image ?? '',
    thumbnail: candidate.thumbnail ?? '',
    width: candidate.width ?? 0,
    height: candidate.height ?? 0,
  }));
}

async function run(command, argumentsList) {
  await new Promise((resolve, reject) => {
    const child = spawn(command, argumentsList, {
      stdio: ['ignore', 'ignore', 'pipe'],
    });
    let stderr = '';
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${path.basename(command)} failed: ${stderr.trim()}`));
    });
  });
}

async function downloadAndOptimize(candidate, relativeTargetPath) {
  const urls = unique([candidate.image, candidate.thumbnail].filter(Boolean));
  let lastError;
  const temporaryPath = path.join(
    workDirectory,
    `download-${process.pid}-${Date.now()}.img`,
  );
  const targetPath = path.join(workspace, relativeTargetPath);
  for (const url of urls) {
    try {
      const response = await fetchWithRetry(url, {
        headers: { Referer: candidate.url || 'https://duckduckgo.com/' },
      });
      const contentType = response.headers.get('content-type') ?? '';
      if (!contentType.startsWith('image/')) {
        throw new Error(`Unexpected content type: ${contentType}`);
      }
      const bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length < 1_500 || bytes.length > 8_000_000) {
        throw new Error(`Image size ${bytes.length} is outside the accepted range.`);
      }
      await fs.writeFile(temporaryPath, bytes);
      await fs.mkdir(path.dirname(targetPath), { recursive: true });
      await run(cwebpPath, [
        '-quiet',
        '-mt',
        '-q',
        '78',
        '-resize',
        '384',
        '0',
        temporaryPath,
        '-o',
        targetPath,
      ]);
      const optimized = await fs.readFile(targetPath);
      await fs.unlink(temporaryPath).catch(() => {});
      return {
        downloadedFrom: url,
        bytes: optimized.length,
        sha256: sha256(optimized),
      };
    } catch (error) {
      lastError = error;
    }
  }
  await fs.unlink(temporaryPath).catch(() => {});
  throw lastError ?? new Error('No downloadable image URL was available.');
}

await fs.mkdir(workDirectory, { recursive: true });
await fs.mkdir(path.dirname(reportPath), { recursive: true });
const rows = JSON.parse(await fs.readFile(classifiedPath, 'utf8'));
const customerNames = JSON.parse(await fs.readFile(customerNamesPath, 'utf8'));
const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
const imageReview = await loadImageReview();
try {
  rejectedImageUrls = new Set(
    JSON.parse(await fs.readFile(rejectedImageUrlsPath, 'utf8')),
  );
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
try {
  blockedWebImageRows = new Set(
    JSON.parse(await fs.readFile(blockedWebImageRowsPath, 'utf8')),
  );
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
if (refreshScraped) {
  for (const [key, match] of Object.entries(manifest)) {
    if (
      key.startsWith('row-') &&
      String(match?.matchMethod ?? '').startsWith('DuckDuckGo image search')
    ) {
      delete manifest[key];
    }
  }
}
let searchCache = {};
try {
  searchCache = JSON.parse(await fs.readFile(searchCachePath, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

const products = rows
  .filter((row) => row.action === 'Include' && toNumber(row.raw?.[10]) > 0)
  .map((row) => {
    const mapping = customerNames[String(row.excelRow)];
    if (!mapping?.customerName) {
      throw new Error(`Missing customer name for source row ${row.excelRow}.`);
    }
    const barcode = String(row.raw?.[28] ?? '').trim();
    const currentFamily = familyName(mapping.customerName);
    const barcodeMatch = manifest[barcode] ?? null;
    const rowMatchKey = `row-${row.excelRow}`;
    const rowMatch = manifest[rowMatchKey] ?? null;
    const blockedFromWebSearch = blockedWebImageRows.has(row.excelRow);
    const rowMatchIsRejected = rejectedImageUrls.has(
      rowMatch?.externalImageUrl,
    );
    const rowMatchIsUsable =
      !rowMatchIsRejected && !blockedFromWebSearch;
    if (
      applyChanges &&
      rowMatch &&
      !rowMatchIsUsable &&
      String(rowMatch.matchMethod ?? '').startsWith('DuckDuckGo image search')
    ) {
      delete manifest[rowMatchKey];
    }
    return {
      row: row.excelRow,
      barcode,
      name: mapping.customerName,
      family: currentFamily,
      brand: String(mapping.canonicalBrand ?? '').trim(),
      category: row.category,
      blockedFromWebSearch,
      existingMatch: barcodeMatch ?? (rowMatchIsUsable ? rowMatch : null),
    };
  });

const groupsByKey = new Map();
for (const product of products.filter(
  (product) => !product.existingMatch && !product.blockedFromWebSearch,
)) {
  const key = `${normalizeText(product.brand)}|${normalizeText(product.family)}`;
  const group = groupsByKey.get(key) ?? {
    key,
    name: product.family,
    brand: product.brand,
    category: product.category,
    products: [],
  };
  group.products.push(product);
  groupsByKey.set(key, group);
}

const groups = [...groupsByKey.values()].sort((left, right) => {
  if (left.products.length !== right.products.length) {
    return right.products.length - left.products.length;
  }
  if (Boolean(left.brand) !== Boolean(right.brand)) return left.brand ? -1 : 1;
  return left.name.localeCompare(right.name);
});

let coveredRows = new Set(
  products.filter((product) => product.existingMatch).map((product) => product.row),
);
const accepted = [];
const rejected = [];
let newQueryCount = 0;
let rateLimitStop = false;

for (let index = 0; index < groups.length; index += 1) {
  const group = groups[index];
  if (coveredRows.size / products.length >= targetCoverage) break;
  const nameTokens = unique(tokensFor(group.name));
  const brandTokens = unique(tokensFor(group.brand));
  const informativeTokens = nameTokens.filter(
    (token) =>
      !brandTokens.includes(token) && !lowInformationWords.has(token),
  );
  if ((!group.brand && informativeTokens.length < 2) || informativeTokens.length === 0) {
    rejected.push({
      key: group.key,
      name: group.name,
      brand: group.brand,
      rows: group.products.map((product) => product.row),
      reason: 'The name is too broad for a safe automatic image match.',
    });
    continue;
  }

  const query = `${group.name} ${categorySearchHint(group.category)} India retail pack`;
  let cached = searchCache[group.key];
  const cachedImageWasRejected = rejectedImageUrls.has(
    cached?.selected?.image,
  );
  if (
    (!cached ||
      refreshScraped ||
      cachedImageWasRejected ||
      (refreshRejected && !cached.accepted)) &&
    newQueryCount < maxQueries
  ) {
    try {
      const candidates = await searchImages(query);
      const scored = candidates
        .map((candidate) => scoreCandidate(group, candidate))
        .sort(
          (left, right) =>
            right.score - left.score ||
            right.sourceWeight - left.sourceWeight ||
            right.width * right.height - left.width * left.height,
        );
      const selected = scored.find(
        (candidate) =>
          candidate.brandPass &&
          candidate.namePass &&
          candidate.formPass &&
          !candidate.rejectedDomain &&
          !candidate.rejectedImage &&
          candidate.score >= minimumScore,
      );
      cached = {
        query,
        searchedAt: new Date().toISOString(),
        accepted: Boolean(selected),
        selected: selected ?? null,
        topCandidates: scored.slice(0, 5),
      };
      searchCache[group.key] = cached;
      newQueryCount += 1;
      await fs.writeFile(searchCachePath, `${JSON.stringify(searchCache, null, 2)}\n`);
      if (newQueryCount % 10 === 0) {
        console.log(
          `Searched ${newQueryCount} new groups; coverage ${coveredRows.size}/${products.length} (${(
            (coveredRows.size / products.length) *
            100
          ).toFixed(1)}%).`,
        );
      }
      await sleep(delayMs);
    } catch (error) {
      cached = {
        query,
        searchedAt: new Date().toISOString(),
        accepted: false,
        error: error.message,
        topCandidates: [],
      };
      searchCache[group.key] = cached;
      await fs.writeFile(searchCachePath, `${JSON.stringify(searchCache, null, 2)}\n`);
      newQueryCount += 1;
      if (/HTTP (202|403|429)|image-search token/i.test(error.message)) {
        rateLimitStop = true;
        console.warn(`Search provider stopped the run: ${error.message}`);
        break;
      }
      await sleep(delayMs);
    }
  }
  if (!cached) continue;
  if (!cached.accepted || !cached.selected) {
    rejected.push({
      key: group.key,
      name: group.name,
      brand: group.brand,
      query,
      rows: group.products.map((product) => product.row),
      reason: cached.error ?? 'No candidate met the strict brand/name confidence threshold.',
      topCandidates: cached.topCandidates ?? [],
    });
    continue;
  }

  const selected = cached.selected;
  const representativeRow = Math.min(
    ...group.products.map((product) => product.row),
  );
  const fileName = `${String(representativeRow).padStart(4, '0')}-${sha256(group.key).slice(0, 10)}.webp`;
  const relativeTargetPath = `assets/product_images/web/${fileName}`;
  let download = null;
  try {
    const targetPath = path.join(workspace, relativeTargetPath);
    try {
      if (refreshScraped) throw Object.assign(new Error('Refresh requested.'), { code: 'ENOENT' });
      const bytes = await fs.readFile(targetPath);
      download = {
        downloadedFrom: selected.image,
        bytes: bytes.length,
        sha256: sha256(bytes),
        reused: true,
      };
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      if (applyChanges) {
        download = await downloadAndOptimize(selected, relativeTargetPath);
      }
    }
  } catch (error) {
    rejected.push({
      key: group.key,
      name: group.name,
      brand: group.brand,
      query,
      rows: group.products.map((product) => product.row),
      reason: `Selected image could not be downloaded: ${error.message}`,
      selected,
    });
    continue;
  }

  if (applyChanges && !download) continue;
  const sourceHost = hostFor(selected.url) || 'web source';
  const match = {
    assetImagePath: relativeTargetPath,
    externalImageUrl: selected.image,
    sourceUrl: selected.url,
    attribution: `Product image source: ${sourceHost}`,
    searchQuery: query,
    matchScore: selected.score,
    matchMethod: 'DuckDuckGo image search with brand/name/size scoring',
  };
  if (applyChanges) {
    for (const product of group.products) {
      manifest[`row-${product.row}`] = match;
      coveredRows.add(product.row);
    }
  }
  accepted.push({
    key: group.key,
    name: group.name,
    brand: group.brand,
    category: group.category,
    query,
    rows: group.products.map((product) => product.row),
    selected,
    assetImagePath: relativeTargetPath,
    download,
  });
}

if (applyChanges) {
  enforceImageReview(manifest, imageReview);
  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

const report = {
  generatedAt: new Date().toISOString(),
  mode: applyChanges ? 'apply' : 'dry-run',
  activeProductCount: products.length,
  previouslyCoveredCount: products.filter((product) => product.existingMatch).length,
  coveredProductCount: coveredRows.size,
  coveragePercent: Number(((coveredRows.size / products.length) * 100).toFixed(2)),
  targetCoveragePercent: targetCoverage * 100,
  familyGroupCount: groups.length,
  newQueryCount,
  acceptedGroupCount: accepted.length,
  rejectedGroupCount: rejected.length,
  rateLimitStop,
  accepted,
  rejected,
};
await fs.writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
console.log(
  JSON.stringify(
    {
      mode: report.mode,
      reportPath,
      activeProductCount: report.activeProductCount,
      coveredProductCount: report.coveredProductCount,
      coveragePercent: report.coveragePercent,
      newQueryCount,
      acceptedGroupCount: report.acceptedGroupCount,
      rejectedGroupCount: report.rejectedGroupCount,
      rateLimitStop,
    },
    null,
    2,
  ),
);
