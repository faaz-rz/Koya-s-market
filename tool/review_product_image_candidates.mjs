import fs from 'node:fs/promises';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const root = path.resolve(import.meta.dirname, '..');
const run = promisify(execFile);
const read = async (file) => JSON.parse(await fs.readFile(path.join(root, file), 'utf8'));
const inventory = await read('outputs/product_image_review/inventory.json');
const cache = await read('.codex_work/product_images/ddg_search_cache.json');
const indices = process.argv.slice(2).flatMap((value) => value.split(',').map(Number));
const directory = path.join(root, 'outputs/product_image_review/candidates');
await fs.mkdir(directory, { recursive: true });
const results = [];
const tasks = [];
for (const index of indices) {
  const asset = inventory.assets.find((item) => item.index === index);
  const currentUrl = asset.products[0].match.externalImageUrl;
  const related = Object.values(cache).filter((result) =>
    [result.selected, ...(result.topCandidates ?? [])].some((candidate) => candidate?.image === currentUrl));
  const seen = new Set([currentUrl]);
  const candidates = related.flatMap((result) => result.topCandidates ?? [])
    .filter((candidate) => { if (seen.has(candidate.image)) return false; seen.add(candidate.image); return true; })
    .filter((candidate) => !/combo|assorted|pack of [2-9]|\+|set of|babero|krevetac|mantita|koffer/i.test(candidate.title))
    .slice(0, 3);
  for (const [offset, candidate] of candidates.entries()) tasks.push({ index, name: asset.name, rows: asset.products.map((p) => p.row), candidate: offset + 1, ...candidate });
}
let completed = 0;
async function worker() {
  while (tasks.length) {
    const task = tasks.shift();
    const stem = `${task.index}-${task.candidate}`;
    const assetImagePath = `outputs/product_image_review/candidates/${stem}.webp`;
    try {
      const response = await fetch(task.image, { signal: AbortSignal.timeout(12000) });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length > 8000000 || bytes.length < 200) throw new Error(`Unexpected size ${bytes.length}`);
      const temporary = path.join(directory, `${stem}.source`);
      await fs.writeFile(temporary, bytes);
      await run('/opt/homebrew/bin/cwebp', ['-quiet', '-q', '86', '-resize', '512', '0', temporary, '-o', path.join(root, assetImagePath)]);
      results.push({ ...task, assetImagePath });
    } catch (error) { results.push({ ...task, error: error.message }); }
    completed++;
    if (completed % 30 === 0) console.log(`Inspected ${completed} replacement URLs`);
  }
}
await Promise.all(Array.from({ length: 5 }, worker));
results.sort((a, b) => a.index - b.index || a.candidate - b.candidate);
await fs.writeFile(path.join(directory, 'candidates.json'), JSON.stringify(results, null, 2) + '\n');
console.log(JSON.stringify({ downloaded: results.filter((r) => r.assetImagePath).length, failed: results.filter((r) => r.error).length }));
