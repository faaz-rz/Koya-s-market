import fs from 'node:fs/promises';
import path from 'node:path';
import { loadImageReview, root } from './product_image_review.mjs';

const review = await loadImageReview();
const taxonomy = JSON.parse(await fs.readFile(path.join(root,'catalogue/product_categories.json'),'utf8'));
const source = await fs.readFile(path.join(root,'lib/features/store/data/generated_product_catalog.dart'),'utf8');
const byId = new Map(taxonomy.assignments.map((p)=>[p.productId,p]));
const field = (block, key) => {
  const value=block.match(new RegExp(`\\n      ${key}:\\s*("(?:[^"\\\\]|\\\\.)*"),`))?.[1];
  return value ? JSON.parse(value.replace(/\\\$/g,'$')) : '';
};
const products = [...source.matchAll(/    Product\(\n[\s\S]*?\n    \),/g)].map(([block])=>
  Object.fromEntries(['id','name','billingName','barcode','unit','imageAsset'].map((key)=>[key,field(block,key)])));
const decisions = new Map(review.decisions.map((d)=>[d.productId,d]));
const pending = products.filter((p)=>!p.imageAsset).map((p)=>({
  ...p, category:byId.get(p.id).category, row:decisions.get(p.id)?.row ?? null,
  reason:decisions.get(p.id)?.reason ?? 'No product photo supplied in the original image manifest.',
}));
const replacements=review.decisions.filter((d)=>d.replacement);
const quarantined=review.decisions.filter((d)=>!d.replacement);
const cell=(s)=>String(s??'').replaceAll('|','\\|').replaceAll('\n',' ');
const write=(file,data)=>fs.writeFile(path.join(root,file),data);
let report=`# Catalogue review — 7 September 2026\n\n## Completed locally\n\n- Reassigned all ${products.length.toLocaleString('en-IN')} products to ${taxonomy.categories.length} client-facing categories. Grocery & Staples is no longer a customer category.\n- Kept Detergents, Home Care and Fabric Care separate. Combined the repeated pooja headings as Pooja Oils & Items; Basmati, Sauces, and Food Colour & Essences are separate.\n- Visually inspected all 1,391 original image assets on labelled contact sheets, then inspected candidate replacements.\n- Replaced photos for ${replacements.length} products using the evidence recorded below.\n- Removed misleading/unverified image references from ${quarantined.length} products. The old files and original mappings remain recoverable; no products, prices, inventory or orders were deleted.\n- Included the previously omitted open_facts asset folder in the app bundle.\n\n## Still needs store confirmation\n\n${pending.length.toLocaleString('en-IN')} products currently show neutral category placeholders: ${quarantined.length} quarantined mappings plus ${pending.length-quarantined.length} pre-existing missing photos. This is not a claim that every remaining photo is an exact in-store SKU match. Some retained photos have old packaging or incomplete size/variant information.\n\nPlease supply a front-of-pack photo and barcode/size/variant for the [pending products](IMAGE_PHOTO_QUEUE.md). In particular, source names such as “GODZILA SINGLE” and brand-plus-price entries do not establish a unique product. Some source barcodes demonstrably identify a different product. Do not automatically trust a barcode or an image-search title.\n\n## Live-store boundary\n\nThese changes are in the local bundled/demo catalogue. No Supabase connection or live-store photo inventory was available for verification. The category migration and guarded external-image metadata migration are prepared in supabase/migrations, but have not been applied. Production uses store-uploaded images from the controlled product-images bucket; those uploads have not been inspected or overwritten.\n\n## Category counts\n\n| Category | Products |\n|---|---:|\n${taxonomy.categories.map((c)=>`| ${cell(c.name)} | ${taxonomy.assignments.filter((p)=>p.categoryId===c.id).length} |`).join('\n')}\n\n## Replacement evidence\n\n| Source row | Product | Evidence and source |\n|---:|---|---|\n${replacements.map((d)=>`| ${d.row} | ${cell(d.name)} | ${cell(d.evidence)} [Source](${d.replacement.sourceUrl}) |`).join('\n')}\n\n## Reapply and verify\n\nRun from the project directory:\n\n\`\`\`sh\nnode tool/apply_product_image_review.mjs\nnode tool/apply_catalogue_categories.mjs\nnode tool/apply_product_image_review.mjs --check\nnode tool/apply_catalogue_categories.mjs --check\nflutter test\nflutter analyze\n\`\`\`\n\nThe image review is SKU-specific and takes priority over guessed family/barcode mappings. Both asset and remote URL are cleared for quarantined entries. Replacement hashes protect the reviewed image bytes. Do not rerun an old full-catalogue SQL import to deploy this review: it also resets commercial fields. Apply the new, narrow migrations through the normal database workflow instead.\n`;
const reviewDate = new Date(`${review.lastUpdatedAt}T12:00:00Z`).toLocaleDateString('en-GB', {
  day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC',
});
report = report.replace('7 September 2026', reviewDate)
  .replace('## Still needs store confirmation', '## Unresolved image matches')
  .replace('Please supply a front-of-pack photo and barcode/size/variant for the [pending products](IMAGE_PHOTO_QUEUE.md).',
    'The [pending products](IMAGE_PHOTO_QUEUE.md) remain unresolved after the available source checks; none have been filled with guessed same-brand photographs.')
  .replace('pre-existing missing photos.', 'remaining pre-existing missing photos.');
report += `\n## Follow-up sourcing\n\n- Amul Buttermilk now uses the manufacturer-supplied pouch photo; the previous Masti carton is retained only in review history. The store master does not establish its exact regional volume.\n- Added explicit branded-pack matches for Amulya 500 g, Elite Atta 5 kg, Saffola Gold 1 L, Gold Drop 5 L / 15 kg, Everest Sabji / Chhole / Tandoori masalas, Dabur Honey 250 g / 500 g, and the Indian Vicks Inhaler.\n- Loose ingredients use visually checked ingredient photographs rather than a different supplier's branded packet. These are representative photographs, not store-stock photography or certification of origin, grade or organic status.\n- Public source URLs, exact billing targets and asset hashes are recorded for every approval. Source availability does not itself establish commercial reuse permission; keep the attribution and confirm applicable image rights before public deployment.\n- Prepared candidate lists are in replacement_sources_followup.json, replacement_sources_ingredients.json and replacement_sources_additional.json. Unpublished zero-price records were not added to the storefront.\n\n## Validation\n\nSee the [recorded local verification results](VALIDATION.md), including phone-width/text-scaling checks and the unchanged product-data comparison.\n`;
await write('catalogue/CATALOGUE_REVIEW.md',report);
let queue='# Product photo queue\n\nSupply the exact product front, barcode and pack size. A missing photo is not evidence that an arbitrary same-brand photo is correct. Source row is shown where this review has one; use the billing name to match the remaining records.\n';
for(const category of taxonomy.categories){
  const items=pending.filter((p)=>p.category===category.name);
  if(!items.length)continue;
  queue+=`\n## ${category.name} (${items.length})\n\n| Source row | Product | Billing name | Barcode | Why a photo is needed |\n|---:|---|---|---|---|\n${items.map((p)=>`| ${p.row??'—'} | ${cell(p.name)} | ${cell(p.billingName)} | ${cell(p.barcode)||'—'} | ${cell(p.reason)} |`).join('\n')}\n`;
}
await write('catalogue/IMAGE_PHOTO_QUEUE.md',queue);
const sql=(s)=>s == null ? 'null' : "'"+String(s).replaceAll("'","''")+"'";
const migration=`-- Guarded external-image metadata corrections, 2026-09-07.\n-- Never replace store-uploaded images, prices, inventory or product names.\n-- Local review only: this migration has not been applied to a live store.\nbegin;\nwith review(product_id,billing_name,previous_url,replacement_url,attribution,source_url) as (values\n${review.decisions.map((d)=>`  (${sql(d.productId)}::uuid,${sql(d.billingName)},${sql(d.previous.externalImageUrl)},${sql(d.replacement?.externalImageUrl)},${sql(d.replacement?.attribution)},${sql(d.replacement?.sourceUrl)})`).join(',\n')}\n)\nupdate public.products p\nset external_image_url=r.replacement_url, image_attribution=r.attribution, image_source_url=r.source_url\nfrom review r\nwhere p.id=r.product_id and p.source_product_name=r.billing_name\n  and p.external_image_url is not distinct from r.previous_url\n  and coalesce(p.image_path,'')='';\ncommit;\n`;
await write('supabase/migrations/202609070002_review_catalogue_image_metadata.sql',migration);
console.log(JSON.stringify({products:products.length,categories:taxonomy.categories.length,replaced:replacements.length,quarantined:quarantined.length,pending:pending.length},null,2));
