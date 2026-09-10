import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { enforceImageReview, loadImageReview, reviewedImageMatch, root } from './product_image_review.mjs';

const row = { excelRow: 42, productName: 'EXACT PACK 100G', raw: [] };
row.raw[28] = '123456789';
const rejected = { row: 42, billingName: row.productName, barcode: row.raw[28], replacement: null };
const wrong = { assetImagePath: 'wrong.webp', externalImageUrl: 'https://example.com/wrong.jpg' };

test('a reviewed rejection overrides both barcode and family image mappings', () => {
  assert.equal(reviewedImageMatch(row, { '123456789': wrong, 'row-42': wrong }, { decisions: [rejected] }), null);
});

test('only the explicitly approved replacement can override a reviewed rejection', () => {
  const replacement = { assetImagePath: 'approved.webp', externalImageUrl: 'https://example.com/approved.jpg' };
  assert.equal(reviewedImageMatch(row, { '123456789': wrong }, { decisions: [{ ...rejected, replacement }] }), replacement);
});

test('a changed source row must be reviewed again', () => {
  assert.throws(() => reviewedImageMatch({ ...row, productName: 'DIFFERENT PACK' }, {}, { decisions: [rejected] }), /stale/);
});

test('enforcement preserves empty tombstones, unrelated mappings and reviewed image bytes', () => {
  const manifest = { '123456789': wrong, 'row-42': wrong, unrelated: wrong };
  enforceImageReview(manifest, { decisions: [rejected] });
  assert.equal(manifest['123456789'], undefined);
  assert.equal(manifest['row-42'].assetImagePath, '');
  assert.equal(manifest['row-42'].externalImageUrl, '');
  assert.equal(manifest.unrelated, wrong);
  const first = structuredClone(manifest);
  enforceImageReview(manifest, { decisions: [rejected] });
  assert.deepEqual(manifest, first);
});

test('every image decision corresponds to a current category-assigned product', async () => {
  const review = await loadImageReview();
  const catalogue = JSON.parse(await fs.readFile(path.join(root, 'catalogue/product_categories.json'), 'utf8'));
  const products = new Map(catalogue.assignments.map((product) => [product.productId, product]));
  const ids = new Set();
  const rows = new Set();
  for (const decision of review.decisions) {
    assert.ok(!ids.has(decision.productId), 'Duplicate reviewed product');
    assert.ok(!rows.has(decision.row), 'Duplicate reviewed source row');
    ids.add(decision.productId);
    rows.add(decision.row);
    assert.equal(products.get(decision.productId)?.billingName, decision.billingName);
    assert.equal(decision.status, decision.replacement ? 'replaced' : 'photo-required');
  }
});

test('Amul buttermilk uses the manufacturer pouch, with the rejected carton retained only in history', async () => {
  const review = await loadImageReview();
  const decision = review.decisions.find((item) => item.row === 233);
  assert.equal(decision.billingName, 'AMUL BUTTER MILK RS15');
  assert.equal(new URL(decision.replacement.sourceUrl).hostname, 'dudhsagardairy.coop');
  assert.match(decision.replacement.externalImageUrl, /Buttermilk-Pouch/);
  assert.ok(decision.history.length > 0);
  for (const previous of decision.history) {
    assert.notEqual(decision.replacement.sha256, previous.replacement.sha256);
    assert.notEqual(decision.replacement.externalImageUrl, previous.replacement.externalImageUrl);
  }
});

test('Dabur Honey pack sizes have distinct explicitly reviewed photographs', async () => {
  const review = await loadImageReview();
  const small = review.decisions.find((item) => item.row === 2659);
  const large = review.decisions.find((item) => item.row === 2658);
  assert.equal(small.barcode, '8901207025365');
  assert.equal(large.barcode, '8901207025372');
  assert.match(small.replacement.sourceUrl, /250-g/);
  assert.match(large.replacement.sourceUrl, /500-g/);
  assert.notEqual(small.replacement.sha256, large.replacement.sha256);
});
