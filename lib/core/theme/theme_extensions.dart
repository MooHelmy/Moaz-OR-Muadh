import 'package:flutter/material.dart';

extension ThemeExtension on BuildContext {
  // Get theme colors
  Color get primaryColor => Theme.of(this).primaryColor;
  Color get secondaryColor => Theme.of(this).colorScheme.secondary;
  Color get errorColor => Theme.of(this).colorScheme.error;
  Color get surfaceColor => Theme.of(this).colorScheme.surface;
  Color get backgroundColor => Theme.of(this).scaffoldBackgroundColor;

  // Get text colors
  Color get textPrimary =>
      Theme.of(this).textTheme.bodyLarge?.color ?? Colors.black;
  Color get textSecondary =>
      Theme.of(this).textTheme.bodyMedium?.color ?? Colors.grey;
  Color get textHint =>
      Theme.of(this).textTheme.bodySmall?.color ?? Colors.grey;

  // Get theme mode
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  bool get isLightMode => Theme.of(this).brightness == Brightness.light;

  // Text styles
  TextStyle get headingLarge =>
      Theme.of(this).textTheme.displayLarge ?? const TextStyle();
  TextStyle get headingMedium =>
      Theme.of(this).textTheme.displayMedium ?? const TextStyle();
  TextStyle get titleLarge =>
      Theme.of(this).textTheme.titleLarge ?? const TextStyle();
  TextStyle get titleMedium =>
      Theme.of(this).textTheme.titleMedium ?? const TextStyle();
  TextStyle get bodyLarge =>
      Theme.of(this).textTheme.bodyLarge ?? const TextStyle();
  TextStyle get bodyMedium =>
      Theme.of(this).textTheme.bodyMedium ?? const TextStyle();
  TextStyle get bodySmall =>
      Theme.of(this).textTheme.bodySmall ?? const TextStyle();
}
