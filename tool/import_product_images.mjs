import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

const workspace = path.resolve(import.meta.dirname, '..');
const classifiedPath = path.join(
  workspace,
  '.codex_work/product_master/classified_products.json',
);
const outputDir = path.join(workspace, 'outputs/product_image_import');
const inputFlag = process.argv.indexOf('--input');
const inputDir = path.resolve(
  inputFlag >= 0 ? process.argv[inputFlag + 1] : 'product_images_to_import',
);
const shouldApply = process.argv.includes('--apply');
const maxBytes = 5 * 1024 * 1024;
const mimeByExtension = new Map([
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.png', 'image/png'],
  ['.webp', 'image/webp'],
]);

function deterministicUuid(value) {
  const bytes = crypto
    .createHash('sha256')
    .update(value)
    .digest()
    .subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(
    12,
    16,
  )}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const normalizeKey = (value) =>
  String(value ?? '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '-');

const classified = JSON.parse(await fs.readFile(classifiedPath, 'utf8'));
const products = classified
  .filter((row) => row.action === 'Include')
  .map((row) => ({
    id: deterministicUuid(
      `koyas-product-master:${row.excelRow}:${row.productName}`,
    ),
    excelRow: row.excelRow,
    name: row.printName || row.productName,
    barcode: String(row.raw[28] ?? '').trim(),
    itemCode: String(row.itemCode ?? '').trim(),
  }));

const productsByKey = new Map();
for (const product of products) {
  const keys = [
    product.id,
    `row-${product.excelRow}`,
    product.barcode,
    product.itemCode,
  ].filter(Boolean);
  for (const key of keys) {
    const normalized = normalizeKey(key);
    productsByKey.set(normalized, [
      ...(productsByKey.get(normalized) ?? []),
      product,
    ]);
  }
}

const entries = await fs.readdir(inputDir, { withFileTypes: true });
const report = [];
for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
  if (!entry.isFile()) continue;
  const extension = path.extname(entry.name).toLowerCase();
  if (extension === '.md' || entry.name.startsWith('.')) continue;
  const mimeType = mimeByExtension.get(extension);
  const key = normalizeKey(path.basename(entry.name, extension));
  const candidates = productsByKey.get(key) ?? [];
  const filePath = path.join(inputDir, entry.name);
  const stats = await fs.stat(filePath);
  let status = 'ready';
  let message = '';
  if (!mimeType) {
    status = 'rejected';
    message = 'Only JPEG, PNG, and WebP files are supported.';
  } else if (stats.size === 0 || stats.size > maxBytes) {
    status = 'rejected';
    message = 'Image must be between 1 byte and 5 MB.';
  } else if (candidates.length === 0) {
    status = 'unmatched';
    message = 'Filename does not match a barcode, item code, row-N, or UUID.';
  } else if (candidates.length > 1) {
    status = 'ambiguous';
    message = 'Identifier belongs to more than one product; use row-N or UUID.';
  }

  const product = candidates.length === 1 ? candidates[0] : null;
  const imagePath = product
    ? `catalog/${product.id}${extension === '.jpeg' ? '.jpg' : extension}`
    : '';
  report.push({
    file: entry.name,
    status,
    message,
    productId: product?.id ?? '',
    productName: product?.name ?? '',
    sourceRow: product?.excelRow ?? '',
    imagePath,
    bytes: stats.size,
  });
}

if (shouldApply) {
  const supabaseUrl = process.env.SUPABASE_URL?.replace(/\/$/, '');
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  assert.ok(supabaseUrl, 'SUPABASE_URL is required with --apply.');
  assert.ok(
    serviceRoleKey,
    'SUPABASE_SERVICE_ROLE_KEY is required with --apply.',
  );

  for (const item of report.filter((entry) => entry.status === 'ready')) {
    const filePath = path.join(inputDir, item.file);
    const extension = path.extname(item.file).toLowerCase();
    const mimeType = mimeByExtension.get(extension);
    const upload = await fetch(
      `${supabaseUrl}/storage/v1/object/product-images/${item.imagePath}`,
      {
        method: 'POST',
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
          'Content-Type': mimeType,
          'x-upsert': 'true',
        },
        body: await fs.readFile(filePath),
      },
    );
    if (!upload.ok) {
      item.status = 'upload_failed';
      item.message = await upload.text();
      continue;
    }
    const update = await fetch(
      `${supabaseUrl}/rest/v1/products?id=eq.${item.productId}`,
      {
        method: 'PATCH',
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
          'Content-Type': 'application/json',
          Prefer: 'return=minimal',
        },
        body: JSON.stringify({ image_path: item.imagePath }),
      },
    );
    if (!update.ok) {
      item.status = 'database_update_failed';
      item.message = await update.text();
      continue;
    }
    item.status = 'uploaded';
  }
}

await fs.mkdir(outputDir, { recursive: true });
const reportPath = path.join(outputDir, 'import_report.json');
await fs.writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
console.log(
  JSON.stringify(
    {
      mode: shouldApply ? 'apply' : 'dry-run',
      inputDir,
      reportPath,
      counts: Object.fromEntries(
        [...new Set(report.map((item) => item.status))].map((status) => [
          status,
          report.filter((item) => item.status === status).length,
        ]),
      ),
    },
    null,
    2,
  ),
);
