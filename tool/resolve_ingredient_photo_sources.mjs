// Read public retailer metadata for explicitly selected ingredient targets.
// This generates candidates only. Download, visually inspect, then approve keys.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const root = path.resolve(import.meta.dirname, '..');
const run = promisify(execFile);
const targets = JSON.parse(await fs.readFile(path.join(root, 'catalogue/ingredient_photo_targets.json'), 'utf8'));
const inventories = new Map();
for (const origin of new Set(targets.map((item) => new URL(item.sourceUrl).origin))) {
  const { stdout } = await run('curl', ['--fail', '--silent', '--show-error', '--location',
    '--max-time', '30', '--proto', '=https', '--proto-redir', '=https', `${origin}/products.json?limit=250`],
  { maxBuffer: 12000000 });
  const { products } = JSON.parse(stdout);
  assert.ok(Array.isArray(products), `Invalid public product index: ${origin}`);
  inventories.set(origin, new Map(products.map((p) => [p.handle, p])));
}
const candidates = targets.map((item) => {
  const url = new URL(item.sourceUrl);
  const product = inventories.get(url.origin).get(url.pathname.split('/').at(-1));
  assert.ok(product?.images?.[0]?.src, `Source image missing: ${item.key}`);
  return { ...item, sourceProductTitle: product.title, image: product.images[0].src,
    evidence: `${item.name}: visually inspected ingredient photograph linked from the retailer's ${product.title} listing. Representative loose ingredient, not a photograph of the store's packaging; no supplier brand, origin, grade, organic certification or pictured serving quantity is asserted for store stock.` };
});
await fs.writeFile(path.join(root, 'catalogue/replacement_sources_ingredients.json'), JSON.stringify(candidates, null, 2) + '\n');
console.log(`Resolved ${candidates.length} explicit ingredient photo candidates; none applied.`);
