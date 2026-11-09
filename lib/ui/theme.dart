import 'package:flutter/material.dart';

const brand = Color(0xFF2E5B4E);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    brightness: b,
    primary: dark ? const Color(0xFF8CC7B4) : brand,
    surface: dark ? const Color(0xFF151816) : const Color(0xFFFBFBF9),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Pretendard',
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: .5), space: 1),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    chipTheme: base.chipTheme.copyWith(side: BorderSide.none),
  );
}

/// 상태 배지 색
class Tone {
  static Color warn(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? const Color(0xFFE6B45A) : const Color(0xFF9A6200);
  static Color danger(BuildContext c) => Theme.of(c).colorScheme.error;
  static Color muted(BuildContext c) => Theme.of(c).colorScheme.onSurfaceVariant;
}
