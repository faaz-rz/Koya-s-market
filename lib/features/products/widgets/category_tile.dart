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
    super.key,
  });

  final ProductCategory category;
  final VoidCallback onTap;
  final bool compact;

  static String imageAssetFor(String key) => switch (key) {
    'atta' => 'assets/product_images/web/review-2026-9732c8d7b5af.webp',
    'basmati' => 'assets/product_images/web/review-438-b3190e182533.webp',
    'spices' => 'assets/product_images/web/review-1833-97644bcb9b9e.webp',
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
    final padding = compact ? AppSpacing.md : AppSpacing.lg;
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
        (compact ? 72 : 92) +
        (compact ? AppSpacing.sm : AppSpacing.md) +
        labelHeight.ceil() +
        4;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: KoyasSurface(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              height: compact ? 72 : 92,
              decoration: BoxDecoration(
                color: colorFor(category.visualKey),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 2 : 4),
                child: imageAssetFor(category.visualKey).isEmpty
                    ? Icon(
                        iconFor(category.visualKey),
                        color: AppColors.ink,
                        size: compact ? 30 : 38,
                      )
                    : Image.asset(
                        imageAssetFor(category.visualKey),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, _, _) => Icon(
                          iconFor(category.visualKey),
                          color: AppColors.ink,
                          size: compact ? 30 : 38,
                        ),
                      ),
              ),
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
