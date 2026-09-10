// After visual inspection: node tool/approve_sourced_product_images.mjs KEY ...
// Every target is explicit. Existing approvals require their previous hash;
// new decisions require the exact billing name and deterministic source-row ID.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { loadImageReview, reviewPath, root } from './product_image_review.mjs';

const review = await loadImageReview();
const reviewedAt = new Date().toISOString().slice(0, 10);
const keys = process.argv.slice(2);
assert.ok(keys.length, 'Explicit reviewed candidate keys required');
assert.equal(new Set(keys).size, keys.length, 'Duplicate candidate keys');
const assetCopies = [];
const candidates = JSON.parse(await fs.readFile(path.join(root,'outputs/product_image_review/sourced/candidates.json'),'utf8'));
const taxonomy = JSON.parse(await fs.readFile(path.join(root,'catalogue/product_categories.json'),'utf8'));
const sourceRows = JSON.parse(await fs.readFile(path.join(root,'.codex_work/product_master/classified_products.json'),'utf8'));
const manifest = JSON.parse(await fs.readFile(path.join(root,'.codex_work/product_master/product_image_matches.json'),'utf8'));
const uuidFor = (row) => {
  const bytes = createHash('sha256').update(`koyas-product-master:${row.excelRow}:${row.productName}`).digest().subarray(0,16);
  bytes[6]=(bytes[6]&0x0f)|0x50; bytes[8]=(bytes[8]&0x3f)|0x80;
  const hex=bytes.toString('hex');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
};
for(const key of keys) {
  const candidate=candidates.find((c)=>c.key===key);
  assert.ok(candidate, `Unknown candidate ${key}`);
  const bytes=await fs.readFile(path.join(root,candidate.assetImagePath));
  const sha256=createHash('sha256').update(bytes).digest('hex');
  const assetImagePath=`assets/product_images/web/review-${candidate.rows[0]}-${sha256.slice(0,12)}.webp`;
  for(const row of candidate.rows) {
    let decision=review.decisions.find((d)=>d.row===row);
    const source=sourceRows.find((item)=>item.excelRow===row);
    assert.ok(source, `Unknown source row ${row}`);
    const product=taxonomy.assignments.find((item)=>item.productId===uuidFor(source));
    assert.ok(product, `Source row ${row} is not a published product`);
    if (candidate.billingNames) {
      assert.equal(candidate.billingNames[row],source.productName,'Exact billing-name confirmation required');
    } else {
      assert.equal(decision?.name,candidate.name, 'Candidate must name the exact catalogue product');
    }
    if (!decision) {
      assert.ok(candidate.billingNames && candidate.evidence, 'New image decisions need explicit targets and evidence');
      const barcode=String(source.raw?.[28]??'').trim();
      decision={row,productId:product.productId,name:product.name,billingName:source.productName,barcode,
        status:'photo-required',reason:candidate.reason??'Additional source-backed product photo review.',
        previous:manifest[barcode]??manifest[`row-${row}`]??{},replacement:null};
      review.decisions.push(decision);
    }
    if (decision.replacement) {
      assert.equal(candidate.previousSha256?.[row],decision.replacement.sha256,`Row ${row} already has a reviewed image; acknowledge its exact previous hash`);
      decision.history??=[];
      decision.history.push({replacement:decision.replacement,evidence:decision.evidence,supersededAt:reviewedAt,reason:candidate.reason});
    }
    decision.status='replaced';
    decision.reviewedAt=reviewedAt;
    decision.evidence=candidate.evidence??`${candidate.name}: product front visually inspected; exact pack size is specified by the linked retailer listing. Current stock packaging still requires store confirmation.`;
    decision.replacement={assetImagePath,externalImageUrl:candidate.image,
      sourceUrl:candidate.sourceUrl,attribution:`Product image source: ${new URL(candidate.sourceUrl).hostname}`,
      matchMethod:`Explicit product image visual review ${reviewedAt}`,sha256};
  }
  assetCopies.push([path.join(root,candidate.assetImagePath),path.join(root,assetImagePath)]);
}
// Validate the complete batch before copying assets or publishing review data.
for (const [source, destination] of assetCopies) await fs.copyFile(source, destination);
review.lastUpdatedAt=reviewedAt;
review.decisions.sort((a,b)=>a.row-b.row);
await fs.writeFile(reviewPath,JSON.stringify(review,null,2)+'\n');
console.log(`Approved ${keys.length} explicitly reviewed candidate images.`);
