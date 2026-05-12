import 'package:flutter/material.dart';
import 'package:medi_guard/core/theme/app_colors.dart';

class AppThemeDark {
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Primary Colors
      primaryColor: AppColors.primaryDark,
      scaffoldBackgroundColor: AppColors.bgDarkPrimary,

      // Color Scheme
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryDark,
        secondary: AppColors.secondaryDark,
        surface: AppColors.bgDarkSecondary,
        error: AppColors.error,
      ),

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgDarkSecondary,
        foregroundColor: AppColors.textDarkPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: AppColors.textDarkPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Text Theme
      textTheme: TextTheme(
        displayLarge: const TextStyle(
          color: AppColors.textDarkPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
        displayMedium: const TextStyle(
          color: AppColors.textDarkPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: const TextStyle(
          color: AppColors.textDarkPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: const TextStyle(
          color: AppColors.textDarkPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: const TextStyle(
          color: AppColors.textDarkPrimary,
          fontSize: 16,
        ),
        bodyMedium: const TextStyle(
          color: AppColors.textDarkSecondary,
          fontSize: 14,
        ),
        bodySmall: const TextStyle(
          color: AppColors.textDarkSecondary,
          fontSize: 12,
        ),
        labelMedium: const TextStyle(
          color: AppColors.textDarkPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),

      // Outlined Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.borderDark),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgDarkSecondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.textDarkSecondary),
        labelStyle: const TextStyle(color: AppColors.textDarkPrimary),
      ),

      // Card
      cardTheme: CardThemeData(
        color: AppColors.bgDarkSecondary,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.borderDark,
        thickness: 1,
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgDarkSecondary,
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.textDarkSecondary,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgDarkSecondary,
        selectedColor: AppColors.primaryDark,
        labelStyle: const TextStyle(color: AppColors.textDarkPrimary),
        brightness: Brightness.dark,
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: AppColors.textDarkPrimary,
        size: 24,
      ),
    );
  }
}
