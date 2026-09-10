import fs from 'node:fs/promises';
import path from 'node:path';

export const root = path.resolve(import.meta.dirname, '..');
export const reviewPath = path.join(root, 'catalogue/product_image_review.json');
export const loadImageReview = async () => JSON.parse(await fs.readFile(reviewPath, 'utf8'));

// A barcode match is not proof of identity: the source workbook itself can have
// a reused/mistyped barcode. Explicit row reviews take priority over both keys.
export function reviewedImageMatch(row, manifest, review) {
  const decision = review.decisions.find((item) => item.row === row.excelRow);
  if (decision) {
    if (decision.billingName !== row.productName) {
      throw new Error(`Image review is stale for source row ${row.excelRow}`);
    }
    return decision.replacement;
  }
  const barcode = String(row.raw?.[28] ?? '').trim();
  return manifest[barcode] ?? manifest[`row-${row.excelRow}`] ?? null;
}

export function enforceImageReview(manifest, review) {
  for (const decision of review.decisions) {
    // Preserve a tombstone: deleting the row would allow family matching to
    // silently reintroduce the rejected image on the next import.
    const match = decision.replacement ?? {
      assetImagePath: '', externalImageUrl: '', sourceUrl: '', attribution: '',
      matchMethod: 'Identity review: store photo required',
    };
    manifest[`row-${decision.row}`] = match;
    // Conflicting barcode keys are removed; all reviewed rows have explicit
    // row entries. The reviewed resolver above remains the source of truth.
    if (decision.barcode) delete manifest[decision.barcode];
  }
  return manifest;
}
