import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/core/theme/app_colors.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';

void main() {
  test('chip labels keep readable colors in every selection state', () {
    final chipTheme = AppTheme.light.chipTheme;

    expect(chipTheme.backgroundColor, AppColors.surface);
    expect(chipTheme.labelStyle?.color, AppColors.ink);
    expect(chipTheme.selectedColor, AppColors.brandSoft);
    expect(chipTheme.secondaryLabelStyle?.color, AppColors.brand700);
  });

  testWidgets('category chip labels render with explicit contrasting colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Material(
          child: Row(
            children: [
              ChoiceChip(label: Text('All'), selected: false),
              ChoiceChip(label: Text('Grocery & Staples'), selected: true),
            ],
          ),
        ),
      ),
    );

    final unselectedText = tester.widget<Text>(find.text('All'));
    final selectedText = tester.widget<Text>(find.text('Grocery & Staples'));
    final unselectedStyle = DefaultTextStyle.of(
      tester.element(find.text('All')),
    ).style;
    final selectedStyle = DefaultTextStyle.of(
      tester.element(find.text('Grocery & Staples')),
    ).style;

    expect(unselectedText.style, isNull);
    expect(selectedText.style, isNull);
    expect(unselectedStyle.color, AppColors.ink);
    expect(selectedStyle.color, AppColors.brand700);
  });
}
