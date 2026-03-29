import 'package:flutter/material.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
// Near-monochrome palette. No colour accent — ink does everything.

const Color kBg = Color(0xFFF0F0F0);
const Color kSurface = Color(0xFFFFFFFF);
const Color kFill = Color(0xFFEAEAEA); // tab container, inner areas
const Color kBorder = Color(0xFFE2E2E2);
const Color kInk = Color(0xFF141414);
const Color kMuted = Color(0xFF8A8A8A);
const Color kSubtle = Color(0xFFBBBBBB);
const Color kCodeBg = Color(0xFF191919); // dark code card

// Keep these for token completeness; widgets reference them.
const Color kPrimary = kInk;
const Color kPrimaryDark = kInk;
const Color kPrimaryLight = Color(0xFF3A3A3A);
const Color kSurface2 = Color(0xFFF7F7F7);

// ── Typography (no network; avoids google_fonts runtime fetch) ───────────────

/// System UI sans — no [fontFamily] so Flutter uses the platform default.
TextStyle driftSans({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w400,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

/// Monospace stack available without bundling font files.
TextStyle driftMono({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'Courier New',
    fontFamilyFallback: const ['Courier', 'Liberation Mono', 'monospace'],
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
  );
}

// ── Theme ─────────────────────────────────────────────────────────────────────

ThemeData buildDriftTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kInk,
    brightness: Brightness.light,
  ).copyWith(
    primary: kInk,
    secondary: const Color(0xFF3A3A3A),
    surface: kSurface,
    onSurface: kInk,
    outline: kBorder,
  );

  final textTheme = TextTheme(
    headlineLarge: driftSans(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      color: kInk,
      letterSpacing: -0.8,
      height: 1.15,
    ),
    headlineMedium: driftSans(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: kInk,
      letterSpacing: -0.5,
      height: 1.2,
    ),
    titleLarge: driftSans(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: kInk,
      letterSpacing: -0.2,
    ),
    titleMedium: driftSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: kInk,
    ),
    bodyLarge: driftSans(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: kInk,
      height: 1.5,
    ),
    bodyMedium: driftSans(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: kMuted,
      height: 1.5,
    ),
    labelLarge: driftSans(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: kInk,
    ),
    labelMedium: driftSans(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      color: kMuted,
      letterSpacing: 0.1,
    ),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kBg,
    textTheme: textTheme,
  );

  return base.copyWith(
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kBorder),
      ),
    ),
    dividerColor: kBorder,
    dividerTheme: const DividerThemeData(color: kBorder, space: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: driftSans(color: kSubtle, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kInk, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCC3333)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCC3333), width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kInk,
        foregroundColor: Colors.white,
        minimumSize: const Size(80, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: driftSans(fontSize: 14, fontWeight: FontWeight.w600),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: const BorderSide(color: kBorder, width: 1.5),
        minimumSize: const Size(80, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: driftSans(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kMuted,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: driftSans(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: kMuted,
        minimumSize: const Size(34, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
