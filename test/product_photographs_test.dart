import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/products/bundled_product_images.dart';
import 'package:koyas_supermarket/features/store/data/generated_product_catalog.dart';
import 'package:koyas_supermarket/features/store/data/supabase_store_repository.dart';

import 'store_repository_sync_test.dart' as repository;
import 'store_sync_cache_test.dart' as fixtures;

void main() {
  final reviewed = GeneratedProductCatalog.products.firstWhere(
    (p) => p.imageAsset.isNotEmpty,
  );
  test(
    'all reviewed bundled photographs exist; live price/stock updates keep matching photographs',
    () {
      var images = 0;
      for (final p in GeneratedProductCatalog.products.where(
        (p) => p.imageAsset.isNotEmpty,
      )) {
        final live = p.copyWith(
          clearImage: true,
          pricePaise: p.pricePaise + 100,
          stockQuantity: 73,
        );
        expect(
          BundledProductImages.assetFor(live),
          p.imageAsset,
          reason: p.name,
        );
        expect(File(p.imageAsset).existsSync(), true, reason: p.imageAsset);
        images++;
      }
      expect(images, greaterThan(1000));
    },
  );

  test(
    'identity edits cannot reuse another pack photograph and staff uploads supersede bundled photos',
    () {
      final live = reviewed.copyWith(clearImage: true);
      expect(
        BundledProductImages.assetFor(live.copyWith(name: 'Other product')),
        isEmpty,
      );
      expect(
        BundledProductImages.assetFor(live.copyWith(unit: 'Other pack')),
        isEmpty,
      );
      expect(
        BundledProductImages.assetFor(live.copyWith(barcode: 'different')),
        isEmpty,
      );
      expect(
        BundledProductImages.assetFor(
          live.copyWith(
            imagePath: 'new/upload.webp',
            imageUrl: 'https://store.test/new.webp',
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'real sync response with no Storage path resolves local photo while keeping authoritative live stock',
    () async {
      final snapshot = repository.cold();
      final row = fixtures.product(stock: 73)
        ..[0] = reviewed.id
        ..[2] = reviewed.name
        ..[4] = reviewed.unit
        ..[11] = null;
      snapshot['catalogue'] = List.generate(
        64,
        (i) => fixtures.bucket(i, i == 0 ? [row] : []),
      );
      final client = await repository.clientFor(
        (_) async => repository.response(snapshot),
      );
      addTearDown(client.dispose);
      final p = (await SupabaseStoreRepository(
        client: client,
      ).loadStore()).products.single;
      expect(p.imageAsset, reviewed.imageAsset);
      expect(p.imageUrl, null);
      expect(p.stockQuantity, 73);
      expect(p.pricePaise, 8000);
    },
  );
}
