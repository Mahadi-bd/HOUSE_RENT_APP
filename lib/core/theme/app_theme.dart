import 'package:flutter/material.dart';
import 'package:rent_solution/core/theme/app_colors.dart';

/// Light and dark Material 3 themes built from the brand colors.
abstract final class AppTheme {
  /// Light theme.
  static ThemeData light() => _build(Brightness.light);

  /// Dark theme.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      brightness: brightness,
    ).copyWith(
      secondary: isLight ? AppColors.navy : null,
      tertiary: AppColors.green,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Bengali glyphs come from the bundled Noto Sans Bengali font (see README).
      fontFamilyFallback: const ['NotoSansBengali'],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }
}
