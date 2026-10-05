# Customer UI refresh

Verified locally on 5 October 2026, customer version **1.1.5+11**. No backend,
hosting, store submission or production deployment was performed.

## Design scope

The supplied six-screen reference informed the mint/cream/peach backdrop, teal
controls, rounded surfaces, softer shadows, image-led categories, compact product
cards, central cart button, product hero and checkout layout. Existing wording,
client departments, product names, prices, images and business rules remain the
source of truth. The home pickup/delivery subtitle is retained, not replaced by
reference marketing copy. No reference ratings, payment providers or offers were
introduced. At the user's follow-up request, the long home header slogan was
removed in favour of a compact "Koya Stores" title beside the logo and cart;
the pickup/delivery subtitle and other wording remain unchanged.
The pickup banner switches to a stacked layout for enlarged phone text, avoiding
mid-word breaks while leaving the normal-size layout unchanged.
Staff screens retain their separate, flat workspace; shared colour
tokens changed, not admin navigation or permissions.

The Figma skills guided font/token discovery and editable screen/component
assembly. Six editable screen drafts and reusable product/category components
were created using Manrope and existing repository artwork:
[Koya Stores — Customer UI refresh draft](https://www.figma.com/design/tp33JtOGHkYkargEvoG4SA).
Figma's Starter tool limit was reached at the design-context/visual-check step.
The Figma draft is therefore not a fully verified specification; app code and
rendered app screens were finished and checked independently, as requested.

## Layout and motion

- Product grids build lazily and adapt their columns/heights to width and text
  scaling. Category rows retain all 37 client names and representative pictures.
- Cart controls use 44-pixel touch targets. The four existing tab mappings remain
  intact; the central cart opens a pushed route and back returns to the same tab.
- Each moving customer route paints its own opaque gradient, preventing outgoing
  page content from bleeding through transparent scaffolds during transitions.
- Native navigation transitions and iOS swipe-back remain available. Short tab,
  sheet, selection, quantity and image animations respect reduced-motion settings.
- Large text switches cramped totals/control rows to stacked layouts. Login,
  variant selection and deletion content remain scrollable with keyboard/insets.
- The logo scales down on narrow phones without cropping its wordmark. Totals
  align to the right at normal sizes and remain readable with enlarged text.
- Background gradients are static; no full-screen blur or new heavyweight image
  assets were added. Existing image-cache and catalogue/realtime safeguards remain.

## Verified results

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: **210 passing tests**, including customer/admin and
  existing account-deletion, checkout, concurrency and cache regressions.
- Shopping flows: 320, 360, 390, 430, 740 and 768 logical-pixel layouts, including
  landscape, system insets and text scaling up to 3×. Sign-in additionally checks
  320×568 and a simulated keyboard with enlarged text.
- Native swipe-back, reduced-motion destinations, tab/cart/back mappings and
  semantic cart naming have regression coverage. Text/button contrast is checked.
- Two customer screenshot runs plus two deletion screenshot runs passed. The
  customer harness produces 24 screen PNGs at 390/1× and 320/2× in
  `build/qa/customer-ui/`; deletion renders are in `build/qa/`.
- **16 Node tests** for the deletion handler and usage-budget safeguards passed.
  **Two Chromium image-upload tests** passed.
- Customer and admin profile web builds both compiled successfully.
- Both Android profile APKs passed signature verification, ZIP integrity and
  16 KB ZIP alignment checks. `git diff --check` passed.

The APKs are local demos, not signed production releases:
Both were rebuilt after the requested compact-header follow-up, retaining
version 1.1.5+11.

| Build | File | Bytes | Split version code |
| --- | --- | ---: | ---: |
| Modern Android, ARM64 | `build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk` | 64,735,159 | 2011 |
| Older 32-bit ARM | `build/app/outputs/flutter-apk/app-armeabi-v7a-profile.apk` | 62,506,625 | 1011 |

Both report version name 1.1.5, minimum Android API 24 and target API 36. ABI
splits add their architecture prefix to the base version code 11. APK SHA-256:

```text
ARM64: 67336c3062da86d59b355f89b62eaf49b4d3de0ddc304d4afdcb88b77b6e39fe
ARM32: effe5d80a45b229ddabb68cffa4270d938e97d13d15a48d41da07076b0a5bc91
```

## Remaining launch checks

No Android device was connected for this run. Render/widget tests do not prove
GPU frame times on every phone; profile scrolling, route transitions, rapid taps,
keyboard, TalkBack and offline/slow-network behaviour on low-end and current
devices before launch. iOS hardware/build verification is also still required.
Missing exact SKU images remain tracked separately in the catalogue photo queue;
this design task does not substitute category pictures for unidentified packs.

Production Supabase/SMTP verification, realistic staging load/usage measurements,
legal URLs, release signing and deployment remain governed by
`ACCOUNT_DELETION_AND_TRANSITIONS.md` and `FREE_TIER_READINESS.md`. Profile APK
compilation is not proof that a production deployment is ready.
