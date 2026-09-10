import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { enforceImageReview, loadImageReview } from './product_image_review.mjs';

const workspace = path.resolve(import.meta.dirname, '..');
const configPath = path.join(
  workspace,
  '.codex_work/product_images/manual_image_families.json',
);
const manifestPath = path.join(
  workspace,
  '.codex_work/product_master/product_image_matches.json',
);
const classifiedPath = path.join(
  workspace,
  '.codex_work/product_master/classified_products.json',
);
const assetsDirectory = path.join(workspace, 'assets/product_images/web');
const temporaryDirectory = path.join(workspace, '.codex_work/product_images');
const reportPath = path.join(
  workspace,
  'outputs/product_image_import/manual_family_report.json',
);
const cwebpPath = '/opt/homebrew/bin/cwebp';
const userAgent = 'KoyasSupermarket/1.0 (product-image-import)';

const sha256 = (value) =>
  crypto.createHash('sha256').update(value).digest('hex');

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

async function downloadAndOptimize(item) {
  const response = await fetch(item.externalImageUrl, {
    headers: {
      'User-Agent': userAgent,
      Referer: item.sourceUrl,
    },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`${item.id}: image HTTP ${response.status}`);
  const contentType = response.headers.get('content-type') ?? '';
  if (!contentType.startsWith('image/')) {
    throw new Error(`${item.id}: unexpected content type ${contentType}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length < 1_500 || bytes.length > 8_000_000) {
    throw new Error(`${item.id}: invalid source image size ${bytes.length}`);
  }
  const fileName = `manual-${item.id}-${sha256(item.externalImageUrl).slice(0, 8)}.webp`;
  const relativePath = `assets/product_images/web/${fileName}`;
  const temporaryPath = path.join(
    temporaryDirectory,
    `manual-${process.pid}-${Date.now()}.img`,
  );
  await fs.writeFile(temporaryPath, bytes);
  await run(cwebpPath, [
    '-quiet', '-mt', '-q', '82', '-resize', '384', '0',
    temporaryPath, '-o', path.join(workspace, relativePath),
  ]);
  await fs.unlink(temporaryPath).catch(() => {});
  return relativePath;
}

await fs.mkdir(assetsDirectory, { recursive: true });
await fs.mkdir(temporaryDirectory, { recursive: true });
const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
const classifiedRows = JSON.parse(await fs.readFile(classifiedPath, 'utf8'));
let appliedRows = 0;
const failures = [];
const accepted = [];
for (const item of config) {
  try {
    let match;
    if (item.reuseFromRow) {
      const sourceRow = classifiedRows.find(
        (row) => row.excelRow === item.reuseFromRow,
      );
      const sourceBarcode = String(sourceRow?.raw?.[28] ?? '').trim();
      const reused =
        manifest[`row-${item.reuseFromRow}`] ?? manifest[sourceBarcode];
      if (!reused) {
        throw new Error(`reuse row ${item.reuseFromRow} has no image.`);
      }
      match = {
        ...reused,
        matchScore: 100,
        matchMethod: 'Manual same-product family reuse after visual verification',
      };
    } else {
      const assetImagePath = await downloadAndOptimize(item);
      match = {
        assetImagePath,
        externalImageUrl: item.externalImageUrl,
        sourceUrl: item.sourceUrl,
        attribution: item.attribution,
        matchScore: 100,
        matchMethod: 'Manual manufacturer/retailer match after visual verification',
      };
    }
    for (const row of item.rows) {
      manifest[`row-${row}`] = match;
      appliedRows += 1;
    }
    accepted.push({
      id: item.id,
      name: item.id.replaceAll('-', ' '),
      rows: item.rows,
      assetImagePath: match.assetImagePath,
      sourceUrl: match.sourceUrl,
      matchMethod: match.matchMethod,
    });
    console.log(`${item.id}: ${item.rows.length} row(s)`);
  } catch (error) {
    failures.push({ id: item.id, rows: item.rows, error: error.message });
    console.warn(`${item.id}: FAILED — ${error.message}`);
  }
}
enforceImageReview(manifest, await loadImageReview());
await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
await fs.mkdir(path.dirname(reportPath), { recursive: true });
await fs.writeFile(
  reportPath,
  `${JSON.stringify({ generatedAt: new Date().toISOString(), accepted, failures }, null, 2)}\n`,
);
console.log(`Applied ${config.length} verified image families to ${appliedRows} rows.`);
console.log(`Report: ${reportPath}`);
if (failures.length > 0) {
  console.error(`${failures.length} family download(s) failed:`);
  for (const failure of failures) {
    console.error(`- ${failure.id} [${failure.rows.join(', ')}]: ${failure.error}`);
  }
  process.exitCode = 1;
}
