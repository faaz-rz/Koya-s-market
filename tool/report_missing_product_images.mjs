import fs from 'node:fs/promises';
import path from 'node:path';

const workspace = path.resolve(import.meta.dirname, '..');
const rows = JSON.parse(
  await fs.readFile(
    path.join(workspace, '.codex_work/product_master/classified_products.json'),
    'utf8',
  ),
);
const customerNames = JSON.parse(
  await fs.readFile(
    path.join(workspace, '.codex_work/product_names/customer_name_mappings.json'),
    'utf8',
  ),
);
const manifest = JSON.parse(
  await fs.readFile(
    path.join(workspace, '.codex_work/product_master/product_image_matches.json'),
    'utf8',
  ),
);
const outputPath = path.join(
  workspace,
  'outputs/product_image_import/missing_product_images.json',
);

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

const activeProducts = rows
  .filter((row) => row.action === 'Include' && toNumber(row.raw?.[10]) > 0)
  .map((row) => {
    const mapping = customerNames[String(row.excelRow)];
    const barcode = String(row.raw?.[28] ?? '').trim();
    const match = manifest[barcode] ?? manifest[`row-${row.excelRow}`] ?? null;
    return {
      row: row.excelRow,
      barcode,
      name: mapping?.customerName ?? row.printName ?? row.productName,
      family: familyName(mapping?.customerName ?? row.printName ?? row.productName),
      brand: String(mapping?.canonicalBrand ?? '').trim(),
      billingBrand: String(row.brand ?? '').trim(),
      billingGroup: String(row.group ?? '').trim(),
      sourceName: String(row.productName ?? '').trim(),
      sourcePrintName: String(row.printName ?? '').trim(),
      category: row.category,
      subcategory: row.subcategory,
      covered: Boolean(match),
      match,
    };
  });

const missing = activeProducts.filter((product) => !product.covered);
const groupsByKey = new Map();
for (const product of missing) {
  const key = `${normalizeText(product.brand)}|${normalizeText(product.family)}`;
  const group = groupsByKey.get(key) ?? {
    key,
    name: product.family,
    brand: product.brand,
    category: product.category,
    subcategory: product.subcategory,
    rows: [],
    barcodes: [],
    billingBrands: [],
    billingGroups: [],
    sourceNames: [],
  };
  group.rows.push(product.row);
  if (product.barcode) group.barcodes.push(product.barcode);
  if (product.billingBrand) group.billingBrands.push(product.billingBrand);
  if (product.billingGroup) group.billingGroups.push(product.billingGroup);
  if (product.sourceName) group.sourceNames.push(product.sourceName);
  groupsByKey.set(key, group);
}

const unique = (values) => [...new Set(values)];
const groups = [...groupsByKey.values()]
  .map((group) => ({
    ...group,
    barcodes: unique(group.barcodes),
    billingBrands: unique(group.billingBrands),
    billingGroups: unique(group.billingGroups),
    sourceNames: unique(group.sourceNames),
  }))
  .sort(
    (left, right) =>
      right.rows.length - left.rows.length ||
      Boolean(right.brand) - Boolean(left.brand) ||
      left.name.localeCompare(right.name),
  );

const report = {
  generatedAt: new Date().toISOString(),
  activeProductCount: activeProducts.length,
  coveredProductCount: activeProducts.length - missing.length,
  coveragePercent: Number(
    (((activeProducts.length - missing.length) / activeProducts.length) * 100).toFixed(2),
  ),
  missingProductCount: missing.length,
  missingBarcodeCount: missing.filter((product) => product.barcode).length,
  missingGroupCount: groups.length,
  brandedGroupCount: groups.filter((group) => group.brand).length,
  unbrandedGroupCount: groups.filter((group) => !group.brand).length,
  groups,
};

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`);
console.log(
  JSON.stringify(
    {
      outputPath,
      activeProductCount: report.activeProductCount,
      coveredProductCount: report.coveredProductCount,
      coveragePercent: report.coveragePercent,
      missingProductCount: report.missingProductCount,
      missingBarcodeCount: report.missingBarcodeCount,
      missingGroupCount: report.missingGroupCount,
      brandedGroupCount: report.brandedGroupCount,
      unbrandedGroupCount: report.unbrandedGroupCount,
      topGroups: groups.slice(0, 80),
    },
    null,
    2,
  ),
);
