import 'package:flutter/material.dart';

// Applied to the Home shell only. Existing routes keep their current theme.
abstract final class AritoriaColors {
  static const olive = Color(0xFF3E5B46);
  static const sage = Color(0xFF8CA68F);
  static const cream = Color(0xFFFAF7F2);
  static const sand = Color(0xFFE7DDC9);
  static const taupe = Color(0xFFC9BBA1);
  static const ink = Color(0xFF2D352E);
  static const muted = Color(0xFF72766C);
  static const line = Color(0xFFE8E5DC);
  static const onPhoto = Color(0xFFFFFDF8);
  // Warm charcoal with a restrained olive undertone, used only over the hero.
  static const photoShadeMid = Color(0xA62C2D25);
  static const photoShade = Color(0xD92C2D25);
  static const transparent = Colors.transparent;
  static const moss = Color(0xFF60683F);
  static const softOlive = Color(0xFFE8E8D5);
  static const card = Color(0xFFFFFCF6);
}

abstract final class AritoriaSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const section = 40.0;
  static const maxWidth = 640.0;
  static const photoRadius = 32.0;
  static const heroRadius = 20.0;
  static const heroMinHeight = 273.0;
  static const heroAirMin = 40.0;
  static const heroAirMax = 60.0;
  static const heroTitleMinScale = 0.8;
}

abstract final class AritoriaType {
  static const homeSection = TextStyle(
    fontFamily: 'Nunito Sans',
    fontSize: 21,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: AritoriaColors.ink,
  );
  static const memberName = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 46,
    height: 1.08,
    fontWeight: FontWeight.w500,
    color: AritoriaColors.ink,
  );
  static const memoryTitle = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 19,
    height: 1.25,
    fontWeight: FontWeight.w500,
    color: AritoriaColors.ink,
  );
  static const question = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 22,
    height: 1.28,
    fontWeight: FontWeight.w500,
    color: AritoriaColors.ink,
  );
  static const brand = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 34,
    height: 1.1,
    color: AritoriaColors.olive,
    fontWeight: FontWeight.w500,
  );
  static const editorial = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 30,
    height: 1.2,
    color: AritoriaColors.onPhoto,
    fontWeight: FontWeight.w500,
  );
  static const section = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 23,
    height: 1.2,
    color: AritoriaColors.ink,
    fontWeight: FontWeight.w500,
  );
  static const body = TextStyle(
    fontFamily: 'Nunito Sans',
    fontSize: 16,
    height: 1.4,
    color: AritoriaColors.ink,
  );
  static const caption = TextStyle(
    fontFamily: 'Nunito Sans',
    fontSize: 12,
    height: 1.4,
    color: AritoriaColors.muted,
  );
  static const action = TextStyle(
    fontFamily: 'Nunito Sans',
    fontSize: 14,
    height: 1.3,
    color: AritoriaColors.olive,
    fontWeight: FontWeight.w700,
  );
}

abstract final class AritoriaDesign {
  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    fontFamily: 'Nunito Sans',
    scaffoldBackgroundColor: AritoriaColors.cream,
    colorScheme: ColorScheme.fromSeed(seedColor: AritoriaColors.olive).copyWith(
      primary: AritoriaColors.olive,
      primaryContainer: AritoriaColors.sand,
      onPrimaryContainer: AritoriaColors.olive,
      secondary: AritoriaColors.sage,
      surface: AritoriaColors.cream,
      onSurface: AritoriaColors.ink,
      onSurfaceVariant: AritoriaColors.muted,
      outlineVariant: AritoriaColors.line,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AritoriaColors.cream,
      foregroundColor: AritoriaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: AritoriaColors.line,
      thickness: 1,
    ),
    textTheme: const TextTheme(
      bodyLarge: AritoriaType.body,
      bodyMedium: AritoriaType.body,
      labelLarge: AritoriaType.action,
    ),
  );
}
