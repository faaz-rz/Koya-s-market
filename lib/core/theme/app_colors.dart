import 'package:flutter/material.dart';

abstract final class AppColors {
  static const heritageIvory = Color(0xFFFFFCF2);

  static const canvas = Color(0xFFF7F9F2);
  static const surface = Color(0xFFFFFEFA);
  static const surfaceMuted = Color(0xFFEDF3EB);
  static const mint = Color(0xFFD8EFE4);
  static const peach = Color(0xFFFFEBD9);

  static const brandSoft = Color(0xFFE0F3E8);
  static const brand300 = Color(0xFF91D7B8);
  static const brand500 = Color(0xFF178467);
  static const brand600 = Color(0xFF087858);
  static const brand700 = Color(0xFF155B43);

  static const ink = Color(0xFF183B2B);
  static const inkSecondary = Color(0xFF53695C);
  static const inkTertiary = Color(0xFF65796B);
  static const outline = Color(0xFFDCE7DD);
  static const outlineStrong = Color(0xFF91AA99);

  static const offer = Color(0xFFBE4C2A);
  static const success = Color(0xFF297544);
  static const warning = Color(0xFF955400);
  static const error = Color(0xFFBA1A1A);
  static const info = Color(0xFF315DA8);

  static const successSoft = Color(0xFFE3F3E7);
  static const warningSoft = Color(0xFFFFF0D9);
  static const errorSoft = Color(0xFFFCE8E6);
  static const infoSoft = Color(0xFFE8F0FE);

  // Product pack photography keeps its original neutral background in both
  // appearances. UI surfaces and text use the theme-aware palette below.
  static const photoCanvas = Color(0xFFFFFEFA);

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light);
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.darkBlend});

  static const light = AppPalette(darkBlend: 0);
  static const dark = AppPalette(darkBlend: 1);
  final double darkBlend;
  bool get isDark => darkBlend >= 0.5;

  Color _tone(Color light, int dark) =>
      Color.lerp(light, Color(dark), darkBlend)!;

  Color get canvas => _tone(AppColors.canvas, 0xFF0C1913);
  Color get heritageIvory => _tone(AppColors.heritageIvory, 0xFF0C1913);
  Color get surface => _tone(AppColors.surface, 0xFF152A20);
  Color get surfaceMuted => _tone(AppColors.surfaceMuted, 0xFF20372A);
  Color get mint => _tone(AppColors.mint, 0xFF173D2D);
  Color get peach => _tone(AppColors.peach, 0xFF342C23);
  Color get brandSoft => _tone(AppColors.brandSoft, 0xFF214433);
  Color get brand300 => _tone(AppColors.brand300, 0xFFA3EBCD);
  Color get brand500 => _tone(AppColors.brand500, 0xFF64D6AC);
  Color get brand600 => _tone(AppColors.brand600, 0xFF76E0B4);
  Color get brand700 => _tone(AppColors.brand700, 0xFFABEFCE);
  Color get ink => _tone(AppColors.ink, 0xFFEDF8F0);
  Color get inkSecondary => _tone(AppColors.inkSecondary, 0xFFBDD1C3);
  Color get inkTertiary => _tone(AppColors.inkTertiary, 0xFFA2BAAA);
  Color get outline => _tone(AppColors.outline, 0xFF2E4938);
  Color get outlineStrong => _tone(AppColors.outlineStrong, 0xFF678775);
  Color get offer => _tone(AppColors.offer, 0xFFFFB393);
  Color get success => _tone(AppColors.success, 0xFF93DFAD);
  Color get warning => _tone(AppColors.warning, 0xFFF3C574);
  Color get error => _tone(AppColors.error, 0xFFFFB4AB);
  Color get info => _tone(AppColors.info, 0xFFA8C7FF);
  Color get successSoft => _tone(AppColors.successSoft, 0xFF203D2C);
  Color get warningSoft => _tone(AppColors.warningSoft, 0xFF3A3020);
  Color get errorSoft => _tone(AppColors.errorSoft, 0xFF442721);
  Color get infoSoft => _tone(AppColors.infoSoft, 0xFF253548);
  Color get onBrand => _tone(AppColors.surface, 0xFF082B1E);
  Color get shadow => _tone(const Color(0x10153524), 0x40000000);

  Color resolve(Color color) => switch (color) {
    AppColors.canvas => canvas,
    AppColors.surface => surface,
    AppColors.surfaceMuted => surfaceMuted,
    AppColors.mint => mint,
    AppColors.peach => peach,
    AppColors.brandSoft => brandSoft,
    AppColors.brand300 => brand300,
    AppColors.brand500 => brand500,
    AppColors.brand600 => brand600,
    AppColors.brand700 => brand700,
    AppColors.ink => ink,
    AppColors.inkSecondary => inkSecondary,
    AppColors.inkTertiary => inkTertiary,
    AppColors.outline => outline,
    AppColors.outlineStrong => outlineStrong,
    AppColors.offer => offer,
    AppColors.success => success,
    AppColors.warning => warning,
    AppColors.error => error,
    AppColors.info => info,
    AppColors.successSoft => successSoft,
    AppColors.warningSoft => warningSoft,
    AppColors.errorSoft => errorSoft,
    AppColors.infoSoft => infoSoft,
    _ => color,
  };

  Color illustrationTint(Color color) =>
      Color.lerp(color, Color.lerp(surface, color, 0.20), darkBlend)!;

  @override
  AppPalette copyWith({double? darkBlend}) =>
      AppPalette(darkBlend: darkBlend ?? this.darkBlend);

  @override
  AppPalette lerp(covariant AppPalette? other, double t) => other == null
      ? this
      : AppPalette(darkBlend: darkBlend + (other.darkBlend - darkBlend) * t);
}
