import fs from 'node:fs/promises';
import path from 'node:path';
import { loadImageReview, reviewedImageMatch } from './product_image_review.mjs';

const root = path.resolve(import.meta.dirname, '..');
const read = async (file) => JSON.parse(await fs.readFile(path.join(root, file), 'utf8'));
const rows = await read('.codex_work/product_master/classified_products.json');
const names = await read('.codex_work/product_names/customer_name_mappings.json');
const manifest = await read('.codex_work/product_master/product_image_matches.json');
const imageReview = await loadImageReview();
const cache = await read('.codex_work/product_images/ddg_search_cache.json');
const candidates = new Map();
for (const result of Object.values(cache)) {
  for (const candidate of [result.selected, ...(result.topCandidates ?? [])].filter(Boolean)) {
    if (!candidates.has(candidate.image)) candidates.set(candidate.image, candidate);
  }
}

const normalize = (text) => String(text ?? '').normalize('NFKD')
  .replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/&/g, ' and ')
  .replace(/[^a-z0-9]+/g, ' ').trim();
function measures(text) {
  return [...String(text).matchAll(/\b(\d+(?:\.\d+)?)\s*(kg|kgs|gms|gm|g|ml|ltr|litre|liter|lt|l)\b/gi)]
    .map((match) => {
      const unit = match[2].toLowerCase();
      return `${Number(match[1]) * (/^(kg|kgs|l|ltr|litre|liter|lt)$/.test(unit) ? 1000 : 1)}${/^(g|gm|gms|kg|kgs)$/.test(unit) ? 'g' : 'ml'}`;
    });
}
const stop = new Set('and of by for with pack variant product premium kg g ml l pc rs retail india buy online best price'.split(' '));
const tokens = (text) => normalize(text).split(' ').filter((word) => word.length > 2 && !/^\d+$/.test(word) && !stop.has(word));
const products = rows.filter((row) => row.action === 'Include' && Number(row.raw[10]) > 0).map((row) => {
  const barcode = String(row.raw[28] ?? '').trim();
  const resolved = reviewedImageMatch(row, manifest, imageReview);
  const match = resolved?.assetImagePath ? resolved : null;
  const candidate = candidates.get(match?.externalImageUrl);
  const name = names[row.excelRow].customerName;
  const brand = names[row.excelRow].canonicalBrand ?? '';
  const sourceTitle = candidate?.title ?? '';
  const sourceText = `${sourceTitle} ${match?.sourceUrl ?? ''}`;
  const productMeasures = [...new Set(measures(name))];
  const sourceMeasures = [...new Set(measures(sourceText.replace(/https?:\/\/\S+/g, '')))];
  const flags = [];
  if (!match) flags.push('missing-image');
  if (productMeasures.length && sourceMeasures.length && !productMeasures.some((size) => sourceMeasures.includes(size))) flags.push('source-size-conflict');
  if (brand && sourceTitle && !normalize(sourceText).replaceAll(' ', '').includes(normalize(brand).replaceAll(' ', ''))) flags.push('source-brand-review');
  const expectedTokens = tokens(name.replace(/\([^)]*\)/g, ''));
  const foundTokens = tokens(sourceText);
  const agreement = expectedTokens.length ? expectedTokens.filter((word) => foundTokens.some((found) => found.startsWith(word) || word.startsWith(found))).length / expectedTokens.length : 0;
  if (match && sourceTitle && agreement < 0.65) flags.push('source-name-review');
  return { row: row.excelRow, name, brand, category: row.category, sourceName: row.productName, sourcePrintName: row.printName, barcode, match, sourceTitle, productMeasures, sourceMeasures, agreement, flags };
});
const assetsByPath = new Map();
for (const product of products.filter((item) => item.match)) {
  const key = product.match.assetImagePath;
  if (!assetsByPath.has(key)) assetsByPath.set(key, { assetImagePath: key, products: [] });
  assetsByPath.get(key).products.push(product);
}
const assets = [...assetsByPath.values()].sort((a, b) => a.products[0].name.localeCompare(b.products[0].name));
for (const [index, asset] of assets.entries()) {
  asset.index = index + 1;
  asset.flags = [...new Set(asset.products.flatMap((product) => product.flags))];
  asset.name = asset.products[0].name;
  const measuresInFamily = new Set(asset.products.flatMap((product) => product.productMeasures));
  if (measuresInFamily.size > 1) asset.flags.push('shared-across-sizes');
  try {
    asset.bytes = (await fs.stat(path.join(root, asset.assetImagePath))).size;
  } catch { asset.flags.push('missing-asset'); }
}
const summary = {
  products: products.length,
  withImages: products.filter((product) => product.match).length,
  missingImages: products.filter((product) => !product.match).length,
  uniqueImages: assets.length,
  sourceSizeConflicts: products.filter((product) => product.flags.includes('source-size-conflict')).length,
  sourceNameReviews: products.filter((product) => product.flags.includes('source-name-review')).length,
  sourceBrandReviews: products.filter((product) => product.flags.includes('source-brand-review')).length,
  sharedAcrossSizes: assets.filter((asset) => asset.flags.includes('shared-across-sizes')).length,
};
const out = path.join(root, 'outputs/product_image_review');
await fs.mkdir(out, { recursive: true });
await fs.writeFile(path.join(out, 'inventory.json'), JSON.stringify({ generatedAt: new Date().toISOString(), summary, products, assets }, null, 2) + '\n');
console.log(JSON.stringify(summary, null, 2));
