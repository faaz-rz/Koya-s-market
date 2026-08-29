# iPhone 6.9-inch screenshots

These six screenshots were captured from the current Flutter customer demo on
an iPhone 17 Pro Max simulator. Each final JPEG is 1320 × 2868 pixels with no
alpha channel, one of Apple's accepted portrait sizes for the 6.9-inch display.

Regenerate after any material UI or catalogue change:

```sh
xcrun simctl boot "iPhone 17 Pro Max"
flutter drive \
  --driver=test_driver/app_store_screenshots_test.dart \
  --target=integration_test/app_store_screenshots_test.dart \
  -d "iPhone 17 Pro Max"
```

The driver initially writes PNGs. Convert them to opaque JPEGs before upload;
App Store screenshots must not contain an alpha channel.
