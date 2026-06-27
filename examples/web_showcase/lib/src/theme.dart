import 'package:flutter/material.dart';

/// Akashi brand palette + dark theme for the showcase.
abstract final class AkashiColors {
  static const background = Color(0xFF0B0D12);
  static const surface = Color(0xFF141822);
  static const surfaceHigh = Color(0xFF1B2030);
  static const border = Color(0xFF252B3B);
  static const primary = Color(0xFF7C5CFF); // cosmic violet
  static const primaryDim = Color(0xFF5B43BF);
  static const accent = Color(0xFF36D6C3); // teal
  static const textPrimary = Color(0xFFEAECF2);
  static const textSecondary = Color(0xFF9AA3B8);
  static const textFaint = Color(0xFF6B7280);
}

/// A monospace stack that resolves on web without bundling a font.
const kMonoFontFamilyFallback = <String>[
  'JetBrains Mono',
  'SF Mono',
  'Menlo',
  'Consolas',
  'monospace',
];

ThemeData buildAkashiTheme() {
  const scheme = ColorScheme.dark(
    primary: AkashiColors.primary,
    onPrimary: Colors.white,
    secondary: AkashiColors.accent,
    onSecondary: Color(0xFF06241F),
    surface: AkashiColors.surface,
    onSurface: AkashiColors.textPrimary,
    error: Color(0xFFFF6B7B),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AkashiColors.background,
    splashFactory: NoSplash.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AkashiColors.textPrimary,
      displayColor: AkashiColors.textPrimary,
    ),
    dividerColor: AkashiColors.border,
    cardTheme: const CardThemeData(
      color: AkashiColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AkashiColors.surfaceHigh,
      side: const BorderSide(color: AkashiColors.border),
      labelStyle: const TextStyle(color: AkashiColors.textPrimary),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AkashiColors.surfaceHigh,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
  );
}
