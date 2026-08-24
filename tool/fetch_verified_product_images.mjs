import fs from 'node:fs/promises';
import path from 'node:path';

const workspace = '/Users/muhammadfaazrazi/Documents/Koyas 2';
const sourcePath = path.join(workspace, '.codex_work/product_master/classified_products.json');
const manifestPath = path.join(workspace, '.codex_work/product_master/product_image_matches.json');
const searchCachePath = path.join(workspace, '.codex_work/product_master/open_facts_search_cache.json');
const reportPath = path.join(workspace, 'outputs/product_image_import/open_food_facts_match_report.json');
const assetDirectory = path.join(workspace, 'assets/product_images');

const services = [
  {
    key: 'food',
    name: 'Open Food Facts',
    origin: 'https://world.openfoodfacts.org',
  },
  {
    key: 'beauty',
    name: 'Open Beauty Facts',
    origin: 'https://world.openbeautyfacts.org',
  },
  {
    key: 'products',
    name: 'Open Products Facts',
    origin: 'https://world.openproductsfacts.org',
  },
];

const userAgent = 'KoyasSupermarket/1.0 (staff@koyas.in)';
const cachedOnly = process.argv.includes('--cached-only');
const batchSize = 40;
const delayBetweenSearchesMs = 7_000;
const fields = [
  'code',
  'product_name',
  'product_name_en',
  'generic_name',
  'brands',
  'quantity',
  'image_front_url',
  'selected_images',
].join(',');

// Every new candidate remains blocked until its pack front has been visually
// compared with the billing name, brand, and size. This avoids accepting a
// miscoded workbook row merely because the external database shares a brand.
const visuallyApprovedBarcodes = new Set([
  '8901063139206', // Britannia Bourbon
  '8901063142015', // Britannia NutriChoice Digestive
  '8901808000785', // Weikfield Cocoa Powder
  '8901808006190', // Weikfield Baking Soda
  '8904103030723', // Swastiks Mango Pickle
  '8904109450112', // Patanjali Dant Kanti
  '8906022340112', // Varalakshmi Sabudana 500 g
  '8906022340419', // Varalakshmi Sabudana 500 g
]);
const visuallyRejectedBarcodes = new Map([
  ['8901396350101', 'Workbook says Dettol shaving cream; the exact-barcode image is Dettol antiseptic liquid.'],
  ['8901595862733', 'Workbook says Schezwan chutney; the exact-barcode image is green chilli sauce.'],
  ['8901595862962', 'Workbook says chilli sauce; the exact-barcode image is Schezwan chutney.'],
  ['8901808000020', 'Workbook says baking soda; the exact-barcode image is baking powder.'],
  ['8901808000068', 'Workbook says 500 g custard powder; the exact-barcode record is 100 g.'],
  ['8901808000181', 'Workbook says 1 kg custard powder; the exact-barcode record is 500 g.'],
]);

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const cleanBarcode = (value) => String(value ?? '').replace(/\D/g, '');
const normalizedBarcode = (value) => cleanBarcode(value).replace(/^0+(?=\d)/, '');
const toNumber = (value) => {
  const parsed = Number(String(value ?? '').replace(/,/g, '').trim());
  return Number.isFinite(parsed) ? parsed : 0;
};
const splitBatches = (values, size) => {
  const batches = [];
  for (let index = 0; index < values.length; index += size) {
    batches.push(values.slice(index, index + size));
  }
  return batches;
};
const textTokens = (value) => new Set(
  String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .split(/\s+/)
    .filter((token) => token.length >= 3 && !/^\d+$/.test(token)),
);
const tokenAgreement = (row, candidate) => {
  const source = textTokens([
    row.productName,
    row.printName,
    row.brand,
  ].filter(Boolean).join(' '));
  const found = textTokens([
    candidate.product_name,
    candidate.product_name_en,
    candidate.generic_name,
    candidate.brands,
    candidate.quantity,
  ].filter(Boolean).join(' '));
  const shared = [...source].filter((token) => found.has(token));
  return {
    sourceTokens: [...source],
    candidateTokens: [...found],
    sharedTokens: shared,
    score: source.size === 0 ? 0 : shared.length / source.size,
  };
};

function selectFrontImage(product) {
  const display = product.selected_images?.front?.display;
  if (display && typeof display === 'object') {
    const languagePriority = ['en', 'hi', 'fr'];
    for (const language of languagePriority) {
      if (display[language]) return display[language];
    }
    const first = Object.values(display).find((value) => typeof value === 'string' && value);
    if (first) return first;
  }
  return typeof product.image_front_url === 'string' ? product.image_front_url : '';
}

async function fetchSearchResponse(service, url) {
  const retryDelays = [0, 12_000, 24_000, 48_000];
  for (let attempt = 0; attempt < retryDelays.length; attempt += 1) {
    if (retryDelays[attempt] > 0) {
      console.log(`${service.name}: retrying after ${retryDelays[attempt] / 1_000}s backoff`);
      await sleep(retryDelays[attempt]);
    }
    const response = await fetch(url, { headers: { 'User-Agent': userAgent } });
    if (response.ok) return response;
    if (![429, 502, 503, 504].includes(response.status) || attempt === retryDelays.length - 1) {
      throw new Error(`${service.name} search failed with HTTP ${response.status}`);
    }
    console.log(`${service.name}: temporary HTTP ${response.status}`);
  }
  throw new Error(`${service.name} search failed after retries`);
}

async function searchService(service, barcodes, searchCache) {
  const result = new Map();
  const serviceCache = searchCache[service.key] ?? { queried: {}, products: {} };
  searchCache[service.key] = serviceCache;
  for (const barcode of barcodes) {
    const cachedProduct = serviceCache.products[barcode];
    if (cachedProduct?.imageUrl) result.set(barcode, cachedProduct);
  }
  const unqueriedBarcodes = barcodes.filter((barcode) => !serviceCache.queried[barcode]);
  const batches = splitBatches(unqueriedBarcodes, batchSize);
  if (batches.length === 0) {
    console.log(`${service.name}: reused cached search results (${result.size} image matches)`);
    return result;
  }
  for (let index = 0; index < batches.length; index += 1) {
    const batch = batches[index];
    const url = new URL('/api/v2/search', service.origin);
    url.searchParams.set('code', batch.join(','));
    url.searchParams.set('fields', fields);
    url.searchParams.set('page_size', String(batch.length));
    url.searchParams.set('sort_by', 'nothing');
    const response = await fetchSearchResponse(service, url);
    const payload = await response.json();
    for (const product of payload.products ?? []) {
      const barcode = normalizedBarcode(product.code);
      const imageUrl = selectFrontImage(product);
      if (barcode && imageUrl) {
        const cachedProduct = { ...product, imageUrl };
        serviceCache.products[barcode] = cachedProduct;
        result.set(barcode, cachedProduct);
      }
    }
    for (const barcode of batch) serviceCache.queried[barcode] = true;
    await fs.writeFile(searchCachePath, `${JSON.stringify(searchCache, null, 2)}\n`);
    console.log(`${service.name}: batch ${index + 1}/${batches.length}, ${result.size} image matches so far`);
    if (index < batches.length - 1) await sleep(delayBetweenSearchesMs);
  }
  return result;
}

async function downloadImage(imageUrl, targetPath) {
  const response = await fetch(imageUrl, { headers: { 'User-Agent': userAgent } });
  if (!response.ok) throw new Error(`Image download failed with HTTP ${response.status}: ${imageUrl}`);
  const contentType = response.headers.get('content-type') ?? '';
  if (!contentType.startsWith('image/')) {
    throw new Error(`Unexpected image content type ${contentType}: ${imageUrl}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length === 0 || bytes.length > 5_000_000) {
    throw new Error(`Image size ${bytes.length} is outside the accepted range: ${imageUrl}`);
  }
  await fs.writeFile(targetPath, bytes);
  return bytes.length;
}

const rows = JSON.parse(await fs.readFile(sourcePath, 'utf8'));
const existingManifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
let searchCache = {};
try {
  searchCache = JSON.parse(await fs.readFile(searchCachePath, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
const displayedRows = rows.filter((row) => row.action === 'Include' && toNumber(row.raw?.[10]) > 0);
const rowsByBarcode = new Map();
for (const row of displayedRows) {
  const barcode = cleanBarcode(row.raw?.[28]);
  if (!barcode) continue;
  const normalized = normalizedBarcode(barcode);
  const matchingRows = rowsByBarcode.get(normalized) ?? [];
  matchingRows.push({ ...row, sourceBarcode: barcode });
  rowsByBarcode.set(normalized, matchingRows);
}

const uniqueRowsByBarcode = new Map(
  [...rowsByBarcode]
    .filter(([, matchingRows]) => matchingRows.length === 1)
    .map(([barcode, matchingRows]) => [barcode, matchingRows[0]]),
);
const duplicateBarcodes = [...rowsByBarcode]
  .filter(([, matchingRows]) => matchingRows.length > 1)
  .map(([barcode, matchingRows]) => ({
    barcode,
    rows: matchingRows.map((row) => ({
      excelRow: row.excelRow,
      productName: row.productName,
      printName: row.printName,
    })),
  }));

const unmatched = new Set(uniqueRowsByBarcode.keys());
const candidates = new Map();
if (cachedOnly) {
  for (const service of services) {
    for (const [barcode, product] of Object.entries(searchCache[service.key]?.products ?? {})) {
      if (!uniqueRowsByBarcode.has(barcode) || !product.imageUrl) continue;
      candidates.set(barcode, { service, product });
      unmatched.delete(barcode);
    }
  }
} else {
  for (let serviceIndex = 0; serviceIndex < services.length; serviceIndex += 1) {
    if (unmatched.size === 0) break;
    const service = services[serviceIndex];
    if (serviceIndex > 0) await sleep(delayBetweenSearchesMs);
    const results = await searchService(service, [...unmatched], searchCache);
    for (const [barcode, product] of results) {
      candidates.set(barcode, { service, product });
      unmatched.delete(barcode);
    }
  }
}

await fs.mkdir(assetDirectory, { recursive: true });
await fs.mkdir(path.dirname(reportPath), { recursive: true });

const manifest = { ...existingManifest };
const accepted = [];
const rejected = [];
for (const [normalized, { service, product }] of candidates) {
  const row = uniqueRowsByBarcode.get(normalized);
  const agreement = tokenAgreement(row, product);
  const barcode = row.sourceBarcode;
  const existing = manifest[barcode];
  const extension = new URL(product.imageUrl).pathname.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
  const assetRelativePath = `assets/product_images/${barcode}.${extension}`;
  const assetAbsolutePath = path.join(workspace, assetRelativePath);

  const visualRejection = visuallyRejectedBarcodes.get(barcode);
  if (visualRejection || (!visuallyApprovedBarcodes.has(barcode) && !existing)) {
    rejected.push({
      barcode,
      excelRow: row.excelRow,
      sourceProductName: row.productName,
      sourcePrintName: row.printName,
      sourceBrand: row.brand,
      candidateProductName: product.product_name || product.product_name_en || '',
      candidateBrand: product.brands || '',
      imageUrl: product.imageUrl,
      sourceUrl: `${service.origin}/product/${cleanBarcode(product.code)}`,
      reason: visualRejection
        ?? 'Exact barcode matched, but this pack front has not yet passed visual name/brand/size approval.',
      agreement,
    });
    continue;
  }

  let bytes = 0;
  try {
    bytes = await downloadImage(product.imageUrl, assetAbsolutePath);
  } catch (error) {
    rejected.push({
      barcode,
      excelRow: row.excelRow,
      sourceProductName: row.productName,
      candidateProductName: product.product_name || product.product_name_en || '',
      imageUrl: product.imageUrl,
      reason: error.message,
      agreement,
    });
    continue;
  }

  manifest[barcode] = {
    assetImagePath: assetRelativePath,
    externalImageUrl: product.imageUrl,
    sourceUrl: `${service.origin}/product/${cleanBarcode(product.code)}`,
    attribution: `Product image: ${service.name} · CC BY-SA 3.0`,
  };
  accepted.push({
    barcode,
    excelRow: row.excelRow,
    sourceProductName: row.productName,
    sourcePrintName: row.printName,
    sourceBrand: row.brand,
    candidateProductName: product.product_name || product.product_name_en || '',
    candidateBrand: product.brands || '',
    imageUrl: product.imageUrl,
    sourceUrl: manifest[barcode].sourceUrl,
    assetImagePath: assetRelativePath,
    bytes,
    agreement,
  });
}

const report = {
  generatedAt: new Date().toISOString(),
  searchComplete: !cachedOnly,
  displayedProductCount: displayedRows.length,
  displayedRowsWithBarcode: [...rowsByBarcode.values()].reduce((sum, matchingRows) => sum + matchingRows.length, 0),
  uniqueUnambiguousBarcodes: uniqueRowsByBarcode.size,
  duplicateBarcodes,
  exactBarcodeCandidatesWithFrontImage: candidates.size,
  acceptedCount: accepted.length,
  rejectedCount: rejected.length,
  noDatabaseImageCount: cachedOnly ? null : unmatched.size,
  unresolvedBarcodeCount: unmatched.size,
  accepted,
  rejected,
  unresolvedBarcodes: [...unmatched].map((barcode) => {
    const row = uniqueRowsByBarcode.get(barcode);
    return {
      barcode: row.sourceBarcode,
      excelRow: row.excelRow,
      productName: row.productName,
      printName: row.printName,
      brand: row.brand,
    };
  }),
};

await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
await fs.writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);

const unresolvedDescription = cachedOnly
  ? 'remain unsearched or unresolved'
  : 'have no reusable database front image';
console.log(`Accepted ${accepted.length} exact images; ${rejected.length} were rejected; ${unmatched.size} ${unresolvedDescription}.`);
console.log(`Report: ${reportPath}`);
