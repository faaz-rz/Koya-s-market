# Visual refresh — Android build 21

9 October 2026. Version `1.1.5+21`.

The reference establishes the visual direction: soft mint and warm ivory,
emerald actions, rounded cards, subtle depth, simple typography and clear product
photography. The app keeps Manrope and its existing brand and SKU images.

## Shared styling

- Light appearance uses ivory surfaces, mint/peach background washes and deep
  green text. Dark appearance uses deep green surfaces, pale mint actions and
  readable neutral text. Both follow the device's appearance setting.
- Customer and staff applications share the same semantic palette, type styles,
  input fields, cards, navigation highlights, buttons, sheets and dialogs.
- Product photography keeps a neutral background in both appearances. Category
  artwork and fallback illustrations use an appropriate tint for the appearance.
- Primary actions use a subtle emerald/mint gradient. Selected tabs, status
  badges, errors, loading states and disabled controls use shared theme roles.
- Cart, address, authentication, checkout, order updates and inventory callbacks
  retain their existing behavior. Backend/schema and notification delivery are
  unchanged by this visual refresh.

## Figma usage

Figma was used first, as requested. A file was created, its empty canvas and
available Manrope styles were inspected, and available Material 3 libraries were
discovered. The required library search then returned the Starter MCP tool-call
limit. The user explicitly authorized completing the remaining work in the app
after this limit. No completed screen design or component library was created on
the Figma canvas; the implemented Flutter styling and rendered previews are the
reviewable design output.

## Verification

- All 290 Flutter regression tests pass; the analyzer reports no issues.
- ARM64/ARM32 APKs and the configured staff web release build compile
  successfully. The APKs retain the existing package, target SDK and certificate.
- Build 21 installs over build 20 on Android 15 and renders the configured
  sign-in screen in both device appearances, without a startup crash.
- Semantic text, actions and status-color pairs meet a 4.5:1 contrast threshold in
  both appearances. The warning tone was deepened after this check identified
  insufficient contrast.
- Shopping actions pass labeled Android touch-target checks in both appearances.
- Switching appearance preserves the cart and applies to checkout, order details,
  Profile and its edit dialog.
- Customer previews cover 15 screens at 390 px/normal text and 320 px/2× text in
  both appearances: 60 renders. Staff previews cover sign-in, overview, analytics,
  pricing, orders and inventory at 390/1400 px in both appearances: 24 renders.
  Account-deletion initial/code screens add 8 dialog renders.
- The gradient button retains the existing accessible label, loading dimensions
  and repeated-tap protection. The regression suite exercises those behaviors.

The refreshed staff website requires deployment of the latest GitHub source to
Cloudflare. The Android APK includes the customer design directly. APKs produced
for this review use the existing profile/internal-testing signing certificate.
