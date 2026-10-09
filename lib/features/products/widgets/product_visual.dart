import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/config/usage_policy.dart';
import '../models/product.dart';
import 'category_tile.dart';
import 'product_image_cache.dart';

class ProductVisual extends StatelessWidget {
  const ProductVisual({
    required this.product,
    this.radius = AppRadii.lg,
    this.iconSize = 58,
    super.key,
  });

  final Product product;
  final double radius;
  final double iconSize;

  static IconData iconFor(String visualKey) => switch (visualKey) {
    'banana' => Icons.eco_rounded,
    'tomato' => Icons.circle,
    'milk' => Icons.local_drink_rounded,
    'eggs' => Icons.egg_alt_rounded,
    'atta' => Icons.grain_rounded,
    'dal' => Icons.rice_bowl_rounded,
    'oil' => Icons.water_drop_rounded,
    'biscuits' => Icons.cookie_rounded,
    'juice' => Icons.local_bar_rounded,
    'detergent' => Icons.local_laundry_service_rounded,
    'fresh' => Icons.eco_rounded,
    'dairy' => Icons.egg_alt_rounded,
    'staples' => Icons.grain_rounded,
    'breakfast' => Icons.breakfast_dining_rounded,
    'snacks' => Icons.cookie_rounded,
    'beverages' => Icons.local_drink_rounded,
    'personal' => Icons.spa_rounded,
    'baby' => Icons.child_friendly_rounded,
    'household' => Icons.cleaning_services_rounded,
    'health' => Icons.health_and_safety_rounded,
    'pooja' => Icons.local_florist_rounded,
    'general' => Icons.home_repair_service_rounded,
    _ => CategoryTile.iconFor(visualKey),
  };

  static Color colorFor(String visualKey) => switch (visualKey) {
    'banana' => const Color(0xFFFFF0A8),
    'tomato' => const Color(0xFFFFD1C7),
    'milk' => const Color(0xFFDDEAF8),
    'eggs' => const Color(0xFFF2E4D2),
    'atta' => const Color(0xFFFFE6B8),
    'dal' => const Color(0xFFFFDDC9),
    'oil' => const Color(0xFFFFEDB8),
    'biscuits' => const Color(0xFFE8D4B4),
    'juice' => const Color(0xFFFFD8C5),
    'detergent' => const Color(0xFFDDE6F6),
    'fresh' => const Color(0xFFE3F3E7),
    'dairy' => const Color(0xFFDDEAF8),
    'staples' => const Color(0xFFFFE6B8),
    'breakfast' => const Color(0xFFFFE4C7),
    'snacks' => const Color(0xFFFFDDC9),
    'beverages' => const Color(0xFFD9EEF4),
    'personal' => const Color(0xFFF4DFEA),
    'baby' => const Color(0xFFE1ECFA),
    'household' => const Color(0xFFE5E2F4),
    'health' => const Color(0xFFDDF0E6),
    'pooja' => const Color(0xFFFFE7C2),
    'general' => const Color(0xFFE8E8E8),
    _ => CategoryTile.colorFor(visualKey),
  };

  @override
  Widget build(BuildContext context) {
    final imageBytes = product.imageBytes;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: AppColors.photoCanvas,
          child: Image.memory(
            imageBytes,
            cacheWidth: UsagePolicy.imageDecodePixels,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _Fallback(
              visualKey: product.visualKey,
              radius: radius,
              iconSize: iconSize,
            ),
          ),
        ),
      );
    }
    final imageAsset = product.imageAsset;
    if (imageAsset.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: AppColors.photoCanvas,
          child: Image.asset(
            imageAsset,
            cacheWidth: UsagePolicy.imageDecodePixels,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _Fallback(
              visualKey: product.visualKey,
              radius: radius,
              iconSize: iconSize,
            ),
          ),
        ),
      );
    }
    final imageUrl = product.imageUrl;
    final imageUri = imageUrl == null ? null : Uri.tryParse(imageUrl);
    if (imageUri != null &&
        imageUri.scheme == 'https' &&
        imageUri.host.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: imageUri.toString(),
          cacheManager: kIsWeb ? null : productImageCache,
          memCacheWidth: UsagePolicy.imageDecodePixels,
          fadeInDuration: AppMotion.duration(
            context,
            const Duration(milliseconds: 160),
          ),
          fadeOutDuration: Duration.zero,
          fit: BoxFit.contain,
          placeholder: (context, url) => _Fallback(
            visualKey: product.visualKey,
            radius: radius,
            iconSize: iconSize,
          ),
          errorWidget: (context, url, error) => _Fallback(
            visualKey: product.visualKey,
            radius: radius,
            iconSize: iconSize,
          ),
        ),
      );
    }
    return _Fallback(
      visualKey: product.visualKey,
      radius: radius,
      iconSize: iconSize,
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.visualKey,
    required this.radius,
    required this.iconSize,
  });

  final String visualKey;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.of(
        context,
      ).illustrationTint(ProductVisual.colorFor(visualKey)),
      child: Center(
        child: Icon(
          ProductVisual.iconFor(visualKey),
          size: iconSize,
          color: AppColors.of(context).ink.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}
