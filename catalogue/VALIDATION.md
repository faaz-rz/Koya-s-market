# Catalogue validation — 10 September 2026

- `flutter test --no-pub`: 122 tests passed.
- `node --test tool/product_image_review_test.mjs`: seven tests passed, including the Amul pouch/history regression and distinct Dabur Honey pack-size images.
- `flutter analyze --no-pub`: no issues found.
- `node tool/apply_product_image_review.mjs --check`: 929 decisions reflected in the catalogue; 104 replacements, 825 photo-required entries; replacement file hashes match.
- `node tool/apply_catalogue_categories.mjs --check`: all 3,193 products assigned to the 37 published, non-empty departments.
- `node tool/audit_product_images.mjs`: zero missing asset files and zero references to rejected mappings. 1,990 products reference 1,070 unique images. The remaining 1,203 products use neutral placeholders (825 quarantined mappings and 378 remaining original gaps).
- Compared every generated product against the existing Git version: all fields other than category IDs, category visuals and image metadata are unchanged. Product names, IDs, prices, units and stock were preserved.
- Category labels were scrolled into view at widths 320, 360, 375, 390, 414, 430 and 768 logical pixels with text scaling at 100%, 130% and 200%; no overflow exceptions.
- Both 390 × 844 previews passed and were visually inspected with real Manrope and Material Icons fonts and loaded assets: the category screen and six corrected branded-product cards. Reproduce with `flutter test --no-pub tool/catalogue_preview_test.dart`; previews are written to `outputs/catalogue_review/categories-phone.png` and `outputs/catalogue_review/corrected-products-phone.png`. Out-of-stock controls reflect unchanged source inventory.
- The 10 September sourcing pass corrected or added images for 65 additional active products. Including previous passes, 104 explicit image replacements are recorded; this is not a count of every retained photo being certified exact.
- `git diff --check`: passed.

## Pre-commit verification

The exact staged catalogue/card/category changes were exported into a clean temporary copy, excluding the unrelated receipt-printing and home-tagline edits still in the working tree.

- `flutter test --no-pub`: all 118 tests in the staged snapshot passed (the 122-test working-tree run above also included four uncommitted receipt tests).
- `node --test tool/product_image_review_test.mjs`: all seven tests passed in the staged snapshot.
- `flutter analyze --no-pub`: no issues in either the staged snapshot or working tree.
- Customer and admin release web builds both passed in the staged snapshot, including their Wasm dry runs.
- All 18 changed JavaScript tools passed syntax checks; staged whitespace checks passed.

These are local automated/layout checks, not physical-device certification or a guarantee that every retained image depicts the store's exact stock. The live Supabase database, uploaded photos and SQL migrations have not been exercised against a live store. See [the review](CATALOGUE_REVIEW.md) and [photo queue](IMAGE_PHOTO_QUEUE.md) for outstanding confirmation.
