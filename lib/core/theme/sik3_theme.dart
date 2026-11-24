import 'package:flutter/material.dart';

/// SiK3 brand & semantic palette derived from the official shield-gear logo.
abstract final class Sik3Colors {
  static const Color navy = Color(0xFF0D2D4D);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberPressed = Color(0xFFD97706);
  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color scannerDark = Color(0xFF0B192C);
  static const Color statusPassed = Color(0xFF15803D);
  static const Color statusReview = Color(0xFFD97706);
  static const Color statusMissing = Color(0xFFDC2626);
  static const Color border = Color(0xFFE2E8F0);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
}

/// Spacing scale anchored to 4dp/8dp rhythm and 48dp minimum touch targets.
abstract final class Sik3Spacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double minTouchTarget = 48.0;
}

/// Concentric corner radii satisfying R_inner = R_outer - P.
abstract final class Sik3Radius {
  static const double outer = 16.0;
  static const double padding = 8.0;
  static const double inner = 8.0;

  static const double cardOuter = 16.0;
  static const double cardPadding = 4.0;
  static const double cardInner = 12.0;

  static const double button = 12.0;
  static const double chip = 8.0;
  static const double pill = 999.0;
}

/// Crisp industrial ease-out motion timings respecting system Reduce Motion.
abstract final class Sik3Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Curve curve = Curves.easeOutCubic;

  static Duration resolve(BuildContext context, Duration duration) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return disableAnimations ? Duration.zero : duration;
  }
}

/// Typography helpers enforcing tabular numerals on dynamic metrics & IDs.
abstract final class Sik3Typography {
  static TextStyle tabular(TextStyle base) {
    return base.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}

/// Builds the Material 3 Android Operate theme for SiK3.
ThemeData buildSik3Theme() {
  const colorScheme = ColorScheme.light(
    primary: Sik3Colors.navy,
    onPrimary: Colors.white,
    secondary: Sik3Colors.amber,
    onSecondary: Sik3Colors.navy,
    surface: Sik3Colors.cardSurface,
    onSurface: Sik3Colors.textPrimary,
    error: Sik3Colors.statusMissing,
    onError: Colors.white,
    outline: Sik3Colors.border,
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Sik3Radius.button),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Sik3Colors.surfaceLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: Sik3Colors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Sik3Colors.cardSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.cardOuter),
        side: const BorderSide(color: Sik3Colors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(
          Sik3Spacing.minTouchTarget,
          Sik3Spacing.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Sik3Spacing.lg,
          vertical: Sik3Spacing.md,
        ),
        shape: buttonShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(
          Sik3Spacing.minTouchTarget,
          Sik3Spacing.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Sik3Spacing.lg,
          vertical: Sik3Spacing.md,
        ),
        side: const BorderSide(color: Sik3Colors.border),
        shape: buttonShape,
        foregroundColor: Sik3Colors.navy,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(
          Sik3Spacing.minTouchTarget,
          Sik3Spacing.minTouchTarget,
        ),
        shape: buttonShape,
        foregroundColor: Sik3Colors.navy,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(
          Sik3Spacing.minTouchTarget,
          Sik3Spacing.minTouchTarget,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Sik3Colors.cardSurface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Sik3Spacing.lg,
        vertical: Sik3Spacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.cardInner),
        borderSide: const BorderSide(color: Sik3Colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.cardInner),
        borderSide: const BorderSide(color: Sik3Colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.cardInner),
        borderSide: const BorderSide(color: Sik3Colors.navy, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.cardInner),
        borderSide: const BorderSide(color: Sik3Colors.statusMissing),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Sik3Colors.border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Sik3Colors.navy,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
