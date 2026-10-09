import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../store/providers/store_provider.dart';

/// Persistent quick-commerce cart entry point for browsing screens.
///
/// It remains in the page flow, so it cannot cover the final product row or
/// conflict with Android and iOS system navigation insets.
class ActiveCartRibbon extends ConsumerWidget {
  const ActiveCartRibbon({this.respectBottomSafeArea = true, super.key});

  final bool respectBottomSafeArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(
      storeProvider.select((store) => store.cartCount),
    );
    final subtotalPaise = ref.watch(
      storeProvider.select((store) => store.subtotalPaise),
    );

    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      reverseDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.bottomCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: cartCount == 0
          ? const SizedBox.shrink(key: ValueKey('empty-cart-ribbon'))
          : SafeArea(
              key: const ValueKey('active-cart-ribbon'),
              top: false,
              bottom: respectBottomSafeArea,
              minimum: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.center,
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Semantics(
                    label: largeText ? 'View cart' : null,
                    child: Material(
                      color: AppColors.of(context).brand700,
                      elevation: 8,
                      shadowColor: AppColors.of(context).shadow,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const Key('view-active-cart'),
                        onTap: () => context.push('/cart'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.of(
                                    context,
                                  ).surface.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.md,
                                  ),
                                ),
                                child: Icon(
                                  Icons.shopping_bag_rounded,
                                  color: AppColors.of(context).surface,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$cartCount ${cartCount == 1 ? 'item' : 'items'} in cart',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: AppColors.of(
                                              context,
                                            ).surface,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    Text(
                                      formatPrice(subtotalPaise),
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.of(
                                              context,
                                            ).surface.withValues(alpha: 0.82),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              if (!largeText)
                                Text(
                                  'View cart',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: AppColors.of(context).surface,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              const SizedBox(width: AppSpacing.xs),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: AppColors.of(context).surface,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
