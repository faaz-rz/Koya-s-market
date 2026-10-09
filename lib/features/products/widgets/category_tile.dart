import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../models/category.dart';

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    required this.category,
    required this.onTap,
    this.compact = false,
    this.horizontal = false,
    super.key,
  });

  final ProductCategory category;
  final VoidCallback onTap;
  final bool compact;
  final bool horizontal;

  static String imageAssetFor(String key) => switch (key) {
    'dal' => 'assets/product_images/web/review-3388-c98f62daa826.webp',
    'atta' => 'assets/product_images/web/review-2026-9732c8d7b5af.webp',
    'grains' => 'assets/product_images/web/review-2817-5871853ff745.webp',
    'millets' => 'assets/product_images/web/review-3372-8646f7f441ad.webp',
    'masala-box' => 'assets/product_images/web/review-2801-e13c28c313dc.webp',
    'garam-masalas' => 'assets/product_images/web/2689-27932001c5.webp',
    'cooking-oils' => 'assets/product_images/web/review-149-1fc84fb401c6.webp',
    'papads' => 'assets/product_images/web/0308-8da1af6ce7.webp',
    'chocolates' => 'assets/product_images/web/0533-b8037542f7.webp',
    'ice-creams' => 'assets/product_images/web/0040-cf9bbfdeb5.webp',
    'ghee' => 'assets/product_images/web/1192-66a3fb61ca.webp',
    'biscuits' => 'assets/product_images/web/0540-6dae1cbf30.webp',
    'tea-coffee' => 'assets/product_images/web/review-2676-e4d1c2d49350.webp',
    'pain-relief' => 'assets/product_images/web/1135-5bff1c2607.webp',
    'basmati' => 'assets/product_images/web/review-438-b3190e182533.webp',
    'spices' => 'assets/product_images/web/review-3021-3c4f39556dda.webp',
    'sauces' => 'assets/product_images/web/2099-0e0d9d6963.webp',
    'food-colour' => 'assets/product_images/web/2259-fe466d56ba.webp',
    'detergents' => 'assets/product_images/web/1261-795ec31bd7.webp',
    'fabric-care' => 'assets/product_images/web/0137-bb3d6cc952.webp',
    'dry-fruits' => 'assets/product_images/web/review-98-50de4e4d94de.webp',
    'salt-sugar' => 'assets/product_images/web/3262-9be36cef3b.webp',
    'pasta' => 'assets/product_images/web/review-1641-3f377fe07567.webp',
    'baking' => 'assets/product_images/web/review-1366-1d451c28cb07.webp',
    'spreads' => 'assets/product_images/web/review-2659-3f890f19751f.webp',
    'pickles' => 'assets/product_images/web/2704-6caba84b2d.webp',
    'body-care' => 'assets/category_images/personal-care.png',
    'kids-care' => 'assets/category_images/baby-care.png',
    'staples' => 'assets/category_images/grocery-staples.png',
    'breakfast' => 'assets/category_images/breakfast-ready-to-cook.png',
    'snacks' => 'assets/category_images/snacks-sweets.png',
    'beverages' => 'assets/category_images/beverages.png',
    'dairy' => 'assets/category_images/dairy-frozen.png',
    'fresh' => 'assets/category_images/fresh-produce.png',
    'personal' => 'assets/category_images/personal-care.png',
    'baby' => 'assets/category_images/baby-care.png',
    'household' => 'assets/category_images/home-care.png',
    'health' => 'assets/category_images/health-wellness.png',
    'pooja' => 'assets/category_images/pooja-festive.png',
    'general' => 'assets/category_images/household-general.png',
    _ => '',
  };

  static IconData iconFor(String key) => switch (key) {
    'dal' => Icons.rice_bowl_rounded,
    'atta' || 'grains' || 'millets' || 'basmati' => Icons.grain_rounded,
    'masala-box' || 'garam-masalas' || 'spices' => Icons.restaurant_rounded,
    'cooking-oils' || 'ghee' => Icons.water_drop_rounded,
    'papads' => Icons.circle_outlined,
    'chocolates' => Icons.cake_rounded,
    'ice-creams' => Icons.icecream_rounded,
    'biscuits' => Icons.cookie_rounded,
    'body-care' => Icons.spa_rounded,
    'kids-care' => Icons.child_friendly_rounded,
    'tea-coffee' => Icons.coffee_rounded,
    'pain-relief' => Icons.healing_rounded,
    'sauces' => Icons.local_dining_rounded,
    'food-colour' => Icons.palette_rounded,
    'detergents' => Icons.local_laundry_service_rounded,
    'fabric-care' => Icons.checkroom_rounded,
    'dry-fruits' => Icons.eco_rounded,
    'salt-sugar' => Icons.bakery_dining_rounded,
    'pasta' => Icons.ramen_dining_rounded,
    'baking' => Icons.cake_rounded,
    'spreads' => Icons.breakfast_dining_rounded,
    'pickles' => Icons.tapas_rounded,
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
    _ => Icons.shopping_basket_rounded,
  };

  static Color colorFor(String key) => switch (key) {
    'dal' ||
    'atta' ||
    'grains' ||
    'millets' ||
    'basmati' ||
    'ghee' ||
    'cooking-oils' ||
    'salt-sugar' => const Color(0xFFFFE6B8),
    'masala-box' ||
    'garam-masalas' ||
    'spices' ||
    'papads' ||
    'sauces' ||
    'pickles' => const Color(0xFFFFDDC9),
    'chocolates' ||
    'biscuits' ||
    'tea-coffee' ||
    'dry-fruits' => const Color(0xFFF0E1CD),
    'body-care' || 'food-colour' => const Color(0xFFF4DFEA),
    'kids-care' || 'ice-creams' => const Color(0xFFE1ECFA),
    'pain-relief' => const Color(0xFFDDF0E6),
    'detergents' || 'fabric-care' => const Color(0xFFE5E2F4),
    'pasta' || 'baking' || 'spreads' => const Color(0xFFFFE4C7),
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
    _ => AppColors.brandSoft,
  };

  static double extentFor(
    BuildContext context, {
    required double width,
    required Iterable<ProductCategory> categories,
    bool compact = false,
  }) {
    final padding = compact ? AppSpacing.xs : AppSpacing.lg;
    final style = compact
        ? Theme.of(context).textTheme.labelMedium
        : Theme.of(context).textTheme.titleMedium;
    var labelHeight = 0.0;
    for (final category in categories) {
      final painter = TextPainter(
        text: TextSpan(text: category.name, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: (width - padding * 2).clamp(1, double.infinity));
      if (painter.height > labelHeight) labelHeight = painter.height;
      painter.dispose();
    }
    return padding * 2 +
        (compact ? 64 : 92) +
        (compact ? AppSpacing.sm : AppSpacing.md) +
        labelHeight.ceil() +
        4;
  }

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return Semantics(
        button: true,
        child: KoyasSurface(
          onTap: onTap,
          radius: AppRadii.xxl,
          padding: const EdgeInsets.all(AppSpacing.md),
          borderColor: AppColors.of(context).surface,
          child: Row(
            children: [
              CategoryPicture(
                visualKey: category.visualKey,
                width: 84,
                height: 84,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  category.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.of(context).brand700,
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      child: KoyasSurface(
        onTap: onTap,
        padding: EdgeInsets.all(compact ? AppSpacing.xs : AppSpacing.lg),
        color: compact
            ? AppColors.of(context).surface.withValues(alpha: 0.7)
            : AppColors.of(context).surface,
        borderColor: compact
            ? Colors.transparent
            : AppColors.of(context).outline,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryPicture(
              visualKey: category.visualKey,
              height: compact ? 64 : 92,
              padding: compact ? 2 : 4,
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            Text(
              category.name,
              textAlign: TextAlign.center,
              style: compact
                  ? Theme.of(context).textTheme.labelMedium
                  : Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// A representative department picture, shared by customer and staff views.
/// Product cards deliberately use their own SKU images, not these pictures.
class CategoryPicture extends StatelessWidget {
  const CategoryPicture({
    required this.visualKey,
    this.width = double.infinity,
    this.height = 92,
    this.padding = 4,
    this.radius = AppRadii.lg,
    super.key,
  });

  final String visualKey;
  final double width;
  final double height;
  final double padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final asset = CategoryTile.imageAssetFor(visualKey);
    final fallback = Icon(
      CategoryTile.iconFor(visualKey),
      color: AppColors.of(context).ink,
      size: (height / 2).clamp(16, 38),
    );
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: asset.startsWith('assets/product_images/')
              ? AppColors.photoCanvas
              : AppColors.of(
                  context,
                ).illustrationTint(CategoryTile.colorFor(visualKey)),
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.all(padding),
        child: asset.isEmpty
            ? fallback
            : Image.asset(
                asset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
