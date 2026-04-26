import 'package:flutter/material.dart';
import '../constants/theme_constants.dart';

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: AppColors.themePrimary,
      scaffoldBackgroundColor: AppColors.lightBgPrimary,
      cardColor: AppColors.lightBgSecondary,
      dividerColor: AppColors.lightBorderPrimary,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.themePrimary,
        foregroundColor: AppColors.lightTextInverse,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightBgSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.lightBorderPrimary),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightBgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.lightBorderPrimary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.lightBorderPrimary),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: AppColors.themePrimary,
        unselectedItemColor: AppColors.lightTextTertiary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.themePrimary,
        foregroundColor: AppColors.lightTextInverse,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: AppColors.darkThemePrimary,
      scaffoldBackgroundColor: AppColors.darkBgPrimary,
      cardColor: AppColors.darkBgSecondary,
      dividerColor: AppColors.darkBorderPrimary,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkThemePrimary,
        foregroundColor: AppColors.darkTextInverse,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkBgSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.darkBorderPrimary),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkBgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.darkBorderPrimary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.darkBorderPrimary),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: AppColors.darkThemePrimary,
        unselectedItemColor: AppColors.darkTextTertiary,
        backgroundColor: AppColors.darkBgPrimary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.darkThemePrimary,
        foregroundColor: AppColors.darkTextInverse,
      ),
    );
  }
}
