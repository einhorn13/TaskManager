import 'package:flutter/material.dart';

/// Цвета эффективного приоритета — используются и в светлой, и в тёмной теме
/// (см. task_manager_plan.md, раздел 4 — движок приоритета).
class PriorityColors {
  static const low = Color(0xFF888780);
  static const medium = Color(0xFF378ADD);
  static const high = Color(0xFFEF9F27);
  static const overdue = Color(0xFFE24B4A);
}

class AppTheme {
  static ThemeData _build(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        dividerTheme: const DividerThemeData(space: 1, thickness: 0.5),
        visualDensity: VisualDensity.standard,
        appBarTheme: AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: scheme.surface,
          titleTextStyle: TextStyle(
              color: scheme.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: scheme.outlineVariant)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: scheme.outlineVariant)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        tooltipTheme:
            const TooltipThemeData(waitDuration: Duration(milliseconds: 450)),
      );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF534AB7),
      brightness: Brightness.light,
    );
    return _build(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF534AB7),
      brightness: Brightness.dark,
    );
    return _build(scheme);
  }
}
