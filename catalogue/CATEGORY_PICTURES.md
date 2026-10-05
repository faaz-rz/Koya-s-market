# Category pictures — 15 September 2026

All 37 client departments now have a bundled representative picture. The shared
mapping is `CategoryTile.imageAssetFor` in
`lib/features/products/widgets/category_tile.dart`. `CategoryPicture` renders it
in customer home/category/search tiles, staff inventory filters, and the product
editor's category dropdown. Unrecognized future departments have a safe icon
fallback. Pictures are decorative beside their readable department labels.

The pictures reuse existing bundled assets; no remote image request, Supabase
Storage configuration, new image download, or catalogue migration is required.
The contact sheet was visually checked, including front-facing replacements for
Garam Masalas and Papads, edible food colouring, and a biscuit packet. Category
pictures identify a department, not a specific SKU or pack size. Product-card
photos and the outstanding `IMAGE_PHOTO_QUEUE.md` remain unchanged.

## Responsive fixes

- Category chips wrap long labels and keep thumbnails within their layout bounds.
- Inventory stock badges and controls wrap on narrow phones and with larger text.
- Overview/analytics cards grow to fit their contents rather than clipping at a
  fixed aspect ratio.
- Product editor category labels wrap alongside pictures; its empty-photo prompt
  can grow with accessibility text settings.

## Local verification

- All 37 pictures are present in Flutter's asset manifest and decode successfully.
- Customer categories: widths 320, 360, 375, 390, 414, 430 and 768; text scales
  1.0, 1.3 and 2.0. Every label and picture is checked while scrolling.
- Admin: widths 320, 390, 430 and 1400 at the same text scales, including overview,
  analytics, all category thumbnails, category filtering, dropdown selection, and
  saving a new product into the selected department without inventing a SKU photo.
- Full Flutter suite and visual previews: 140 passing tests.
- Product-image review: 7 passing Node tests; category/review generators report
  no pending changes. Flutter analysis and Git whitespace checks are clean.
- Customer and admin release web builds pass, including Wasm compatibility dry
  runs. These unconfigured release builds retain their production configuration
  gates; they are not deployed production sites.

Reproduce with:

```sh
flutter analyze --no-pub
flutter test --no-pub test tool/catalogue_preview_test.dart
node --test tool/product_image_review_test.mjs
node tool/apply_catalogue_categories.mjs --check
node tool/apply_product_image_review.mjs --check
python3 tool/category_image_sheet.py
```

The optional contact-sheet command requires Pillow. Preview images and run logs
are under ignored `outputs/category_review/` and `outputs/catalogue_review/`.

Vercel deployment, Supabase integration, live cross-device synchronization and
production end-to-end checks are still deferred. Physical iPhone verification is
also blocked by the local Xcode licence prompt; the machine owner must review it
using `sudo xcodebuild -license`. No licence was accepted automatically.
