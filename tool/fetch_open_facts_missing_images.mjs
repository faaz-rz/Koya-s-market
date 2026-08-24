import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

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
const cachePath = path.join(
  workspace,
  '.codex_work/product_images/open_facts_v3_cache.json',
);
const reportPath = path.join(
  workspace,
  'outputs/product_image_import/open_facts_missing_report.json',
);
const assetDirectory = path.join(
  workspace,
  'assets/product_images/open_facts',
);

const applyChanges = process.argv.includes('--apply');
const refresh = process.argv.includes('--refresh');
const cwebpPath = '/opt/homebrew/bin/cwebp';
const userAgent = 'KoyasSupermarket/1.0 (product-image-import)';

const knownWrongWorkbookBarcodeMatches = new Map([
  ['8901396350101', 'The billing row says shaving cream; the barcode record is antiseptic liquid.'],
  ['8901595862733', 'The billing row says Schezwan chutney; the barcode record is green chilli sauce.'],
  ['8901595862962', 'The billing row says chilli sauce; the barcode record is Schezwan chutney.'],
  ['8901808000020', 'The billing row says baking soda; the barcode record is baking powder.'],
  ['8901808000068', 'The billing row says 500 g custard powder; the barcode record is 100 g.'],
  ['8901808000181', 'The billing row says 1 kg custard powder; the barcode record is 500 g.'],
]);
const visuallyApprovedBarcodes = new Set([
  '8901088062428', // Set Wet Cool Hold Hair Gel
  '690225101172', // India Gate Classic Basmati Rice 1 kg
  '8901499008169', // Kellogg's Chocos
  '8906036300041', // Peanut Chikki
  '8906016579986', // ITC HomeLites matchbox
  '8901725192426', // Bingo snack pack
  '8901399900013', // Wipro Garnet 9W LED bulb
  '8901030705847', // TRESemme Hair Fall Defense Shampoo
  '840222000149', // L.G. Hing Powder 50 g
  '8901063325357', // Britannia Toastea Rusk
  '8901523111407', // Sabena Dishwash Powder 900 g
]);

const stopWords = new Set([
  'and', 'classic', 'for', 'free', 'india', 'pack', 'packet', 'piece',
  'pieces', 'regular', 'set', 'special', 'the', 'variant', 'with',
]);
const formWords = new Set([
  'atta', 'balm', 'bar', 'battery', 'biscuit', 'blade', 'brush', 'chutney',
  'coil', 'cream', 'detergent', 'gel', 'ghee', 'henna', 'incense', 'liquid',
  'lotion', 'masala', 'mat', 'oil', 'powder', 'razor', 'salt', 'sauce',
  'shampoo', 'soap', 'spray', 'sticks', 'talc', 'tea', 'toothpaste',
]);

const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));
const toNumber = (value) => {
  const parsed = Number(String(value ?? '').replace(/,/g, '').trim());
  return Number.isFinite(parsed) ? parsed : 0;
};
const cleanBarcode = (value) => String(value ?? '').replace(/\D/g, '');
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
        !/^\d+(?:g|kg|ml|l)?$/.test(token),
    );
const unique = (values) => [...new Set(values)];
const sha256 = (value) =>
  crypto.createHash('sha256').update(value).digest('hex');

function selectFrontImage(product) {
  const display = product.selected_images?.front?.display;
  if (display && typeof display === 'object') {
    for (const language of ['en', 'hi', 'mr', 'ta', 'te']) {
      if (display[language]) return display[language];
    }
    const first = Object.values(display).find(
      (value) => typeof value === 'string' && value,
    );
    if (first) return first;
  }
  return typeof product.image_front_url === 'string'
    ? product.image_front_url
    : '';
}

function sourceDetails(responseUrl) {
  const host = new URL(responseUrl).hostname;
  if (host.includes('openbeautyfacts')) {
    return { name: 'Open Beauty Facts', origin: 'https://world.openbeautyfacts.org' };
  }
  if (host.includes('openproductsfacts')) {
    return { name: 'Open Products Facts', origin: 'https://world.openproductsfacts.org' };
  }
  if (host.includes('openpetfoodfacts')) {
    return { name: 'Open Pet Food Facts', origin: 'https://world.openpetfoodfacts.org' };
  }
  return { name: 'Open Food Facts', origin: 'https://world.openfoodfacts.org' };
}

function candidateAgreement(group, product) {
  const sourceBrand = unique(tokensFor(group.brand));
  const sourceName = unique(
    tokensFor(group.name).filter((token) => !sourceBrand.includes(token)),
  );
  const candidateText = [
    product.product_name,
    product.product_name_en,
    product.generic_name,
    product.brands,
    product.quantity,
  ].filter(Boolean).join(' ');
  const candidateTokens = new Set(tokensFor(candidateText));
  const sharedBrand = sourceBrand.filter((token) => candidateTokens.has(token));
  const sharedName = sourceName.filter((token) => candidateTokens.has(token));
  const sourceForms = sourceName.filter((token) => formWords.has(token));
  const candidateForms = [...candidateTokens].filter((token) => formWords.has(token));
  const conflictingForms =
    sourceForms.length > 0 &&
    candidateForms.length > 0 &&
    !sourceForms.some((token) => candidateForms.includes(token));
  const brandPass =
    sourceBrand.length === 0 ||
    sharedBrand.length >= Math.min(1, sourceBrand.length);
  const namePass =
    sharedName.length >= Math.min(1, Math.max(1, sourceName.length));
  return {
    sourceBrand,
    sourceName,
    candidateTokens: [...candidateTokens],
    sharedBrand,
    sharedName,
    sourceForms,
    candidateForms,
    conflictingForms,
    accepted: (brandPass || sharedName.length >= 2) && namePass && !conflictingForms,
  };
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

async function fetchProduct(barcode) {
  const url = new URL(
    `/api/v3/product/${barcode}.json`,
    'https://world.openfoodfacts.org',
  );
  url.searchParams.set('product_type', 'all');
  url.searchParams.set(
    'fields',
    'code,product_type,product_name,product_name_en,generic_name,brands,quantity,image_front_url,selected_images',
  );
  for (const delay of [0, 2_000, 6_000, 15_000]) {
    if (delay) await sleep(delay);
    const response = await fetch(url, {
      headers: { 'User-Agent': userAgent },
      redirect: 'follow',
      signal: AbortSignal.timeout(25_000),
    });
    if (response.status === 404) return { found: false };
    if (response.ok) {
      const payload = await response.json();
      if (!payload.product) return { found: false };
      return {
        found: true,
        product: payload.product,
        responseUrl: response.url,
      };
    }
    if (![429, 500, 502, 503, 504].includes(response.status)) {
      throw new Error(`HTTP ${response.status}`);
    }
  }
  throw new Error('Open Facts lookup failed after retries.');
}

async function downloadAndOptimize(imageUrl, relativeTargetPath, sourceUrl) {
  const response = await fetch(imageUrl, {
    headers: {
      'User-Agent': userAgent,
      Referer: sourceUrl,
    },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`Image HTTP ${response.status}`);
  const contentType = response.headers.get('content-type') ?? '';
  if (!contentType.startsWith('image/')) {
    throw new Error(`Unexpected content type: ${contentType}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length < 1_500 || bytes.length > 8_000_000) {
    throw new Error(`Image size ${bytes.length} is outside the accepted range.`);
  }
  const temporaryPath = path.join(
    workspace,
    '.codex_work/product_images',
    `open-facts-${process.pid}-${Date.now()}.img`,
  );
  const targetPath = path.join(workspace, relativeTargetPath);
  await fs.writeFile(temporaryPath, bytes);
  await fs.mkdir(path.dirname(targetPath), { recursive: true });
  await run(cwebpPath, [
    '-quiet', '-mt', '-q', '80', '-resize', '384', '0',
    temporaryPath, '-o', targetPath,
  ]);
  await fs.unlink(temporaryPath).catch(() => {});
  const optimized = await fs.readFile(targetPath);
  return { bytes: optimized.length, sha256: sha256(optimized) };
}

await fs.mkdir(path.dirname(cachePath), { recursive: true });
await fs.mkdir(path.dirname(reportPath), { recursive: true });
await fs.mkdir(assetDirectory, { recursive: true });

const rows = JSON.parse(await fs.readFile(classifiedPath, 'utf8'));
const names = JSON.parse(await fs.readFile(customerNamesPath, 'utf8'));
const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
let cache = {};
try {
  cache = JSON.parse(await fs.readFile(cachePath, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

const missingByBarcode = new Map();
for (const row of rows) {
  if (row.action !== 'Include' || toNumber(row.raw?.[10]) <= 0) continue;
  const barcode = cleanBarcode(row.raw?.[28]);
  if (!barcode || manifest[barcode] || manifest[`row-${row.excelRow}`]) continue;
  const mapping = names[String(row.excelRow)];
  if (!mapping?.customerName) continue;
  const group = missingByBarcode.get(barcode) ?? {
    barcode,
    name: familyName(mapping.customerName),
    brand: String(mapping.canonicalBrand ?? '').trim(),
    rows: [],
  };
  group.rows.push(row.excelRow);
  missingByBarcode.set(barcode, group);
}

const accepted = [];
const rejected = [];
const notFound = [];
let queried = 0;
for (const group of missingByBarcode.values()) {
  let result = cache[group.barcode];
  if (!result || refresh) {
    try {
      result = await fetchProduct(group.barcode);
    } catch (error) {
      result = { found: false, error: error.message };
    }
    result.queriedAt = new Date().toISOString();
    cache[group.barcode] = result;
    queried += 1;
    await fs.writeFile(cachePath, `${JSON.stringify(cache, null, 2)}\n`);
    if (queried % 20 === 0) {
      console.log(`Queried ${queried}/${missingByBarcode.size} missing barcodes.`);
    }
    await sleep(550);
  }
  if (!result.found || !result.product) {
    notFound.push({ ...group, error: result.error ?? '' });
    continue;
  }
  const imageUrl = selectFrontImage(result.product);
  const agreement = candidateAgreement(group, result.product);
  const knownRejection = knownWrongWorkbookBarcodeMatches.get(group.barcode);
  if (
    !imageUrl ||
    knownRejection ||
    (!agreement.accepted && !visuallyApprovedBarcodes.has(group.barcode))
  ) {
    rejected.push({
      ...group,
      candidateName: result.product.product_name ?? result.product.product_name_en ?? '',
      candidateBrand: result.product.brands ?? '',
      candidateQuantity: result.product.quantity ?? '',
      imageUrl,
      reason: knownRejection ?? (!imageUrl
        ? 'The exact barcode has no selected front image.'
        : 'The exact barcode text conflicts with or does not sufficiently confirm the billing name.'),
      agreement,
    });
    continue;
  }

  const source = sourceDetails(result.responseUrl);
  const sourceUrl = `${source.origin}/product/${group.barcode}`;
  const fileName = `${group.barcode}-${sha256(imageUrl).slice(0, 10)}.webp`;
  const relativeTargetPath = `assets/product_images/open_facts/${fileName}`;
  let download = null;
  try {
    try {
      const bytes = await fs.readFile(path.join(workspace, relativeTargetPath));
      download = { bytes: bytes.length, sha256: sha256(bytes), reused: true };
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      if (applyChanges) {
        download = await downloadAndOptimize(imageUrl, relativeTargetPath, sourceUrl);
      }
    }
  } catch (error) {
    rejected.push({
      ...group,
      candidateName: result.product.product_name ?? '',
      candidateBrand: result.product.brands ?? '',
      imageUrl,
      reason: `Image download failed: ${error.message}`,
      agreement,
    });
    continue;
  }
  if (applyChanges && !download) continue;
  const match = {
    assetImagePath: relativeTargetPath,
    externalImageUrl: imageUrl,
    sourceUrl,
    attribution: `Product image: ${source.name} · CC BY-SA 3.0`,
    searchQuery: `Exact barcode ${group.barcode} with product_type=all`,
    matchScore: 100,
    matchMethod: 'Open Facts v3 exact-barcode cross-database match',
  };
  if (applyChanges) manifest[group.barcode] = match;
  accepted.push({
    ...group,
    candidateName: result.product.product_name ?? result.product.product_name_en ?? '',
    candidateBrand: result.product.brands ?? '',
    candidateQuantity: result.product.quantity ?? '',
    imageUrl,
    sourceUrl,
    assetImagePath: relativeTargetPath,
    agreement,
    download,
  });
}

if (applyChanges) {
  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}
const report = {
  generatedAt: new Date().toISOString(),
  mode: applyChanges ? 'apply' : 'dry-run',
  missingBarcodeGroupCount: missingByBarcode.size,
  newlyQueriedCount: queried,
  acceptedCount: accepted.length,
  rejectedCount: rejected.length,
  notFoundCount: notFound.length,
  accepted,
  rejected,
  notFound,
};
await fs.writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify({
  reportPath,
  missingBarcodeGroupCount: report.missingBarcodeGroupCount,
  newlyQueriedCount: report.newlyQueriedCount,
  acceptedCount: report.acceptedCount,
  rejectedCount: report.rejectedCount,
  notFoundCount: report.notFoundCount,
}, null, 2));
