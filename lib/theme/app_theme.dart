import 'package:flutter/material.dart';

class AppColors {
  /// アプリ全体の基調色（ミント寄りのグリーン）
  static const seed = Color(0xFF2E9E6E);

  // PFCの色。画面のどこでも同じ色で示し、文字を読まなくても見分けられるようにする
  // （たんぱく質＝肉や魚の赤、脂質＝油の黄、炭水化物＝ご飯の青）。
  static const protein = Color(0xFFE06C75);
  static const fat = Color(0xFFE5A93A);
  static const carbs = Color(0xFF4A90D9);

  /// 目標を超えたときの色
  static const over = Color(0xFFD64545);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
