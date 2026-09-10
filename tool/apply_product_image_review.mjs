// Image-only synchronization. Never regenerate stock, prices, names or old SQL
// imports to apply an image correction. --check performs no writes.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { enforceImageReview, loadImageReview, root } from './product_image_review.mjs';

const review = await loadImageReview();
const check = process.argv.includes('--check');
const file = path.join(root, 'lib/features/store/data/generated_product_catalog.dart');
const before = await fs.readFile(file, 'utf8');
const decisions = new Map(review.decisions.map((item) => [item.productId, item]));
assert.equal(decisions.size, review.decisions.length, 'Duplicate product review');
const rowsSeen = new Set();
const imageFields = /\n      (?:imageAsset|imageUrl|imageAttribution):\s*"(?:[^"\\]|\\.)*",/g;
const dartString = (value) => JSON.stringify(value).replace(/\$/g, '\\$');
let changed = 0;

for (const decision of review.decisions) {
  assert.ok(!rowsSeen.has(decision.row), `Duplicate row ${decision.row}`);
  rowsSeen.add(decision.row);
  assert.ok(['replaced', 'photo-required'].includes(decision.status));
  assert.equal(decision.status === 'replaced', decision.replacement !== null);
  if (!decision.replacement) continue;
  const replacement = decision.replacement;
  assert.ok(replacement.assetImagePath.startsWith('assets/product_images/'));
  assert.ok(!replacement.assetImagePath.includes('..'));
  assert.equal(new URL(replacement.externalImageUrl).protocol, 'https:');
  assert.equal(new URL(replacement.sourceUrl).protocol, 'https:');
  const bytes = await fs.readFile(path.join(root, replacement.assetImagePath));
  assert.equal(createHash('sha256').update(bytes).digest('hex'), replacement.sha256,
    `Reviewed image content changed: ${replacement.assetImagePath}`);
}

const seen = new Set();
const after = before.replace(/    Product\(\n[\s\S]*?\n    \),/g, (block) => {
  const id = block.match(/\n      id: "([^"]+)"/)?.[1];
  const decision = decisions.get(id);
  if (!decision) return block;
  seen.add(id);
  assert.ok(block.includes(`billingName: ${dartString(decision.billingName)},`),
    `Billing name changed for reviewed product ${id}`);
  const clean = block.replace(imageFields, '');
  const match = decision.replacement;
  const fields = match ? [
    `      imageAsset: ${dartString(match.assetImagePath)},`,
    `      imageUrl: ${dartString(match.externalImageUrl)},`,
    `      imageAttribution: ${dartString(match.attribution)},`,
  ].join('\n') : '';
  // Compare values rather than layout so dart format doesn't break --check.
  const expected = {
    imageAsset: match?.assetImagePath ?? '',
    imageUrl: match?.externalImageUrl ?? '',
    imageAttribution: match?.attribution ?? '',
  };
  const equivalent = Object.entries(expected).every(([key, value]) => {
    const actual = block.match(new RegExp(`\\n      ${key}:\\s*("(?:[^"\\\\]|\\\\.)*"),`))?.[1];
    return actual === undefined ? value === '' : actual === dartString(value);
  });
  if (equivalent) return block;
  changed++;
  return clean.replace('\n    ),', `${fields ? '\n' + fields : ''}\n    ),`);
});
assert.equal(seen.size, decisions.size, 'Review contains unknown product IDs');
assert.equal(before.replace(imageFields, ''), after.replace(imageFields, ''),
  'Image review must not modify non-image product fields');
if (check) {
  assert.equal(changed, 0, `${changed} image decisions have not been applied`);
} else {
  if (before !== after) await fs.writeFile(file, after);
  const manifestPath = path.join(root, '.codex_work/product_master/product_image_matches.json');
  try {
    const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
    await fs.writeFile(manifestPath, JSON.stringify(enforceImageReview(manifest, review), null, 2) + '\n');
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
console.log(JSON.stringify({mode: check ? 'check' : 'apply', decisions: decisions.size,
  replaced: review.decisions.filter((d) => d.replacement).length,
  photoRequired: review.decisions.filter((d) => !d.replacement).length, changed}, null, 2));
