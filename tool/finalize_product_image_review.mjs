// One-time assembly of the 2026-09-06 manually reviewed inventory snapshot.
// This does NOT decide identity from text, scores, OCR, or search titles.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { root, reviewPath } from './product_image_review.mjs';

const read = async (file) => JSON.parse(await fs.readFile(path.join(root, file), 'utf8'));
assert.equal(await fs.stat(reviewPath).then(() => true, () => false), false,
  'Review already finalized. Use approve_sourced_product_images.mjs for later corrections.');
const inventory = await read('outputs/product_image_review/inventory.json');
assert.equal(inventory.assets.length, 1391, 'Use the original review snapshot only');
const findings = await read('catalogue/image_review_findings.json');
const approvals = await read('catalogue/approved_image_replacements.json');
const candidates = await read('outputs/product_image_review/candidates/candidates.json');
const sourced = await read('outputs/product_image_review/sourced/candidates.json');

// Explicitly retained after review: back/side labels, promotional layouts, and
// several misleading initial impressions which proved to be the right item.
// These are NOT certified exact-SKU photographs; unresolved packaging remains
// documented separately. Wrong products in advertisements are not exempt.
const retained = new Set([
  1,13,20,21,82,103,104,108,109,113,138,144,150,187,201,220,245,249,258,
  272,290,314,315,317,322,331,366,386,391,400,439,495,536,577,580,581,
  598,646,648,650,653,683,695,710,712,714,719,723,795,809,818,827,
  843,844,851,859,864,865,887,917,952,953,961,962,969,989,1042,1053,
  1073,1081,1090,1110,1120,1137,1140,1184,1190,1198,1209,1212,1215,
  1219,1220,1229,1273,1292,1293,1297,1304,1311,1313,1321,1328,
  1340,1349,1352,1357,1387,
]);
const correctedReasons = new Map([
  [17, 'Kabuli chana photo is not verified for the abbreviated billing item DP A500G; store identification required.'],
  [57, 'Milky Mist photo conflicts with Jersey in billing name and Amul in customer title. Confirm brand before attaching a pack photo.'],
  [119, 'Aloe-vera black-henna photo is not verified for the ambiguous billing item BANJARA ALV.'],
  [399, 'Adani red chilli photo is wrong; billing name W PEPPER PDR EV indicates Everest white pepper powder.'],
  [994, 'Branded small white-pepper jar is unverified for loose 100 g white pepper; colour itself is correct.'],
  [995, 'Branded small white-pepper jar is unverified for loose 1 kg white pepper; colour itself is correct.'],
  [552, 'Ready-to-eat Gokul snack dal is unverified for the grocery billing item MDAL.'],
  [555, 'Photo does not establish the grocery wheat SKU from supplier Gokul; store photo required.'],
]);
function idFor(product) {
  const bytes = createHash('sha256').update(`koyas-product-master:${product.row}:${product.sourceName}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 15) | 80; bytes[8] = (bytes[8] & 63) | 128;
  const hex = bytes.toString('hex');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
const decisions = new Map();
for (const finding of findings.findings) {
  if (retained.has(finding.index)) continue;
  const asset = inventory.assets.find((a) => a.index === finding.index);
  for (const product of asset.products) decisions.set(product.row, {
    row: product.row, productId: idFor(product), name: product.name,
    billingName: product.sourceName, barcode: product.barcode,
    status: 'photo-required', reason: correctedReasons.get(finding.index) ?? finding.reason,
    previous: product.match, replacement: null,
  });
}
async function approve(rows, candidate, evidence) {
  const bytes = await fs.readFile(path.join(root, candidate.assetImagePath));
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const assetImagePath = `assets/product_images/web/review-${rows[0]}-${sha256.slice(0,12)}.webp`;
  await fs.copyFile(path.join(root, candidate.assetImagePath), path.join(root, assetImagePath));
  for (const row of rows) {
    const decision = decisions.get(row);
    assert.ok(decision, `Approved replacement must resolve a reviewed finding: ${row}`);
    decision.status = 'replaced';
    decision.evidence = evidence;
    decision.replacement = {
      assetImagePath, externalImageUrl: candidate.image,
      sourceUrl: candidate.sourceUrl ?? candidate.url,
      attribution: candidate.attribution ?? `Product image source: ${new URL(candidate.sourceUrl ?? candidate.url).hostname}`,
      matchMethod: 'Explicit product image visual review 2026-09-06', sha256,
    };
  }
}
for (const approval of approvals.candidates) {
  const candidate = candidates.find((item) => item.index === approval.index && item.candidate === approval.candidate);
  assert.ok(candidate && !candidate.error, `Missing candidate ${approval.index}-${approval.candidate}`);
  await approve(approval.rows, candidate, approval.evidence);
}
for (const approval of approvals.reuse) {
  const asset = inventory.assets.find((item) => item.index === approval.index);
  const match = asset.products[0].match;
  await approve(approval.rows, { ...match, image: match.externalImageUrl }, approval.evidence);
}
for (const candidate of sourced) {
  await approve(candidate.rows, candidate, candidate.evidence ?? `${candidate.name}: product front visually inspected; specified pack size corroborated by the linked product listing.`);
}
const review = {
  reviewedAt: '2026-09-06',
  scope: 'Local bundled catalogue: all 1391 original photos inspected on labelled contact sheets. Not a live database audit or a certificate of exact in-store SKU identity.',
  originalCounts: inventory.summary,
  retainedReviewNotes: findings.findings.filter((f) => retained.has(f.index)).map((f) => ({
    assetImagePath: inventory.assets[f.index-1].assetImagePath,
    rows: inventory.assets[f.index-1].products.map((p) => p.row),
    note: ({439:'Nawhals Fish-to-Fish is a mayonnaise-style sauce; retain.',723:'Gopuram kumkum confirmed on pack; retain.',917:'Oleev Active is a blended oil; retain.',1190:'Sunsilk Super Shine hair serum confirmed on bottle; retain.',1209:'Three Mango is the Swastik product range; retain.',1215:'This image depicts disposable table covers, not toilet-seat covers; retain.'})[f.index] ?? f.reason,
  })),
  decisions: [...decisions.values()].sort((a,b) => a.row-b.row),
};
await fs.writeFile(reviewPath, JSON.stringify(review, null, 2) + '\n');
console.log(JSON.stringify({decisions: review.decisions.length,
  replacements: review.decisions.filter((d) => d.replacement).length,
  photoRequired: review.decisions.filter((d) => !d.replacement).length,
  retainedReviewNotes: review.retainedReviewNotes.length}, null, 2));
