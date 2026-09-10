import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { loadImageReview, reviewedImageMatch } from './product_image_review.mjs';

const workspace = path.resolve(import.meta.dirname, '..');
const classifiedPath = path.join(
  workspace,
  '.codex_work/product_master/classified_products.json',
);
const manifestPath = path.join(
  workspace,
  '.codex_work/product_master/product_image_matches.json',
);
const rejectedUrlsPath = path.join(
  workspace,
  '.codex_work/product_images/rejected_image_urls.json',
);
const webAssetDirectory = path.join(workspace, 'assets/product_images/web');
const reportPath = path.join(
  workspace,
  'outputs/product_image_import/final_image_audit.json',
);

const toNumber = (value) => {
  const parsed = Number(String(value ?? '').replace(/,/g, '').trim());
  return Number.isFinite(parsed) ? parsed : 0;
};

const rows = JSON.parse(await fs.readFile(classifiedPath, 'utf8'));
const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
const imageReview = await loadImageReview();
const rejectedUrls = new Set(JSON.parse(await fs.readFile(rejectedUrlsPath, 'utf8')));
const activeProducts = rows.filter(
  (row) => row.action === 'Include' && toNumber(row.raw?.[10]) > 0,
);

const covered = [];
const missingAssets = [];
const rejectedReferences = [];
for (const row of activeProducts) {
  const barcode = String(row.raw?.[28] ?? '').trim();
  const match = reviewedImageMatch(row, manifest, imageReview);
  if (!match?.assetImagePath) continue;
  const absolutePath = path.join(workspace, match.assetImagePath);
  let stats = null;
  try {
    stats = await fs.stat(absolutePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const item = {
    row: row.excelRow,
    category: row.category,
    barcode,
    assetImagePath: match.assetImagePath,
    sourceUrl: match.sourceUrl ?? '',
    externalImageUrl: match.externalImageUrl ?? '',
    attribution: match.attribution ?? '',
    bytes: stats?.size ?? 0,
  };
  covered.push(item);
  if (!stats?.isFile()) missingAssets.push(item);
  if (rejectedUrls.has(item.externalImageUrl)) rejectedReferences.push(item);
}

const webFiles = (await fs.readdir(webAssetDirectory, { withFileTypes: true }))
  .filter((entry) => entry.isFile() && entry.name.endsWith('.webp'))
  .map((entry) => `assets/product_images/web/${entry.name}`)
  .sort();
const referencedAssets = new Set(covered.map((item) => item.assetImagePath));
const unreferencedWebAssets = webFiles.filter(
  (relativePath) => !referencedAssets.has(relativePath),
);
const uniqueAssets = [...referencedAssets];
const assetBytes = new Map();
for (const relativePath of uniqueAssets) {
  const stats = await fs.stat(path.join(workspace, relativePath));
  assetBytes.set(relativePath, stats.size);
}

const categories = [...new Set(activeProducts.map((row) => row.category))]
  .sort()
  .map((category) => {
    const productCount = activeProducts.filter(
      (row) => row.category === category,
    ).length;
    const coveredCount = covered.filter(
      (item) => item.category === category,
    ).length;
    return {
      category,
      productCount,
      coveredCount,
      coveragePercent: Number(((coveredCount / productCount) * 100).toFixed(2)),
    };
  });

const report = {
  generatedAt: new Date().toISOString(),
  activeProductCount: activeProducts.length,
  coveredProductCount: covered.length,
  coveragePercent: Number(((covered.length / activeProducts.length) * 100).toFixed(2)),
  openFoodFactsProductCount: covered.filter((item) =>
    item.attribution.includes('Open Food Facts'),
  ).length,
  openFactsProductCount: covered.filter((item) =>
    /Open (?:Food|Beauty|Products|Pet Food) Facts/.test(item.attribution),
  ).length,
  webSourcedProductCount: covered.filter((item) =>
    item.assetImagePath.startsWith('assets/product_images/web/'),
  ).length,
  uniqueReferencedAssetCount: uniqueAssets.length,
  webAssetCount: webFiles.length,
  totalReferencedBytes: [...assetBytes.values()].reduce(
    (total, bytes) => total + bytes,
    0,
  ),
  largestAssetBytes: Math.max(...assetBytes.values()),
  missingAssetCount: missingAssets.length,
  unreferencedWebAssetCount: unreferencedWebAssets.length,
  rejectedReferenceCount: rejectedReferences.length,
  categories,
  missingAssets,
  unreferencedWebAssets,
  rejectedReferences,
};

// Coverage is reported, not an identity criterion. A known-wrong photograph
// must never be kept merely to meet a numeric coverage target.
assert.equal(report.missingAssetCount, 0);
// Old files are retained for recovery; their catalogue references are removed.
const quarantinedAssets = new Set(imageReview.decisions.flatMap((d) => [
  d.previous?.assetImagePath,
  ...(d.history ?? []).map((entry) => entry.replacement?.assetImagePath),
]));
assert.deepEqual(unreferencedWebAssets.filter((asset) => !quarantinedAssets.has(asset)), []);
assert.equal(report.rejectedReferenceCount, 0);
assert.ok(report.openFoodFactsProductCount >= 10);
assert.ok(report.openFactsProductCount >= report.openFoodFactsProductCount);
assert.ok(report.webSourcedProductCount > 0);
assert.ok(report.webAssetCount > 0);

await fs.mkdir(path.dirname(reportPath), { recursive: true });
await fs.writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify({ reportPath, ...report, categories: undefined,
  unreferencedWebAssets: undefined, missingAssets: undefined, rejectedReferences: undefined }, null, 2));
