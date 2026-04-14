import 'package:flutter/material.dart';

/// 与 `prototype-ios.html` 中小红书浅/暗色变量对齐的主题（不使用 fromSeed 以免主色被 tonal 偏移）。
abstract final class AppTheme {
  // --- 原型 :root（浅色）---
  static const _bgLight = Color(0xFFF7F8FA);
  static const _surfaceLight = Color(0xFFFFFFFF);
  static const _surfaceSoftLight = Color(0xFFF3F4F7);
  /// 主文字：略浅于纯黑，降低浅色界面下的刺眼感（与 Web `--text-h` 对齐思路）。
  static const _textLight = Color(0xFF2A2633);
  static const _mutedLight = Color(0xFF71717A);
  static const _lineLight = Color(0xFFEBECEF);
  static const _brandLight = Color(0xFFFF2442);
  static const _brandSoftLight = Color(0xFFFFE9ED);
  static const _successLight = Color(0xFF22A06B);

  // --- 原型 body[data-style="dark"] ---
  static const _bgDark = Color(0xFF111216);
  static const _surfaceDark = Color(0xFF1A1B20);
  static const _surfaceSoftDark = Color(0xFF14151A);
  /// 深色模式主文字：偏冷灰而非近白，减轻暗色下的眩光（与 Web 深色主字一致）。
  static const _textDark = Color(0xFFD8DCE6);
  static const _mutedDark = Color(0xFF9CA3AF);
  static const _lineDark = Color(0xFF2A2C34);
  static const _brandDark = Color(0xFFFF4D67);
  static const _brandSoftDark = Color(0xFF3A1E26);

  static ThemeData light() {
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: _brandLight,
      onPrimary: _surfaceLight,
      primaryContainer: _brandSoftLight,
      onPrimaryContainer: _brandLight,
      secondary: _successLight,
      onSecondary: _surfaceLight,
      secondaryContainer: Color(0xFFDFF5EA),
      onSecondaryContainer: Color(0xFF0D3D28),
      tertiary: _mutedLight,
      onTertiary: _surfaceLight,
      tertiaryContainer: _surfaceSoftLight,
      onTertiaryContainer: _textLight,
      error: Color(0xFFBA1A1A),
      onError: _surfaceLight,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: _surfaceLight,
      onSurface: _textLight,
      surfaceContainerHighest: _surfaceSoftLight,
      onSurfaceVariant: _mutedLight,
      outline: _lineLight,
      outlineVariant: _lineLight,
      shadow: Color(0x4018181B),
      scrim: Color(0x80000000),
      inverseSurface: _bgDark,
      onInverseSurface: _textDark,
      inversePrimary: _brandDark,
      surfaceTint: _brandLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bgLight,
      appBarTheme: AppBarTheme(
        backgroundColor: _bgLight,
        foregroundColor: _textLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: _surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _lineLight),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _brandLight,
          foregroundColor: _surfaceLight,
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _brandDark,
      onPrimary: _surfaceLight,
      primaryContainer: _brandSoftDark,
      onPrimaryContainer: _brandDark,
      secondary: Color(0xFF5CD39A),
      onSecondary: Color(0xFF003920),
      secondaryContainer: Color(0xFF005231),
      onSecondaryContainer: Color(0xFF7AF0B3),
      tertiary: _mutedDark,
      onTertiary: _surfaceDark,
      tertiaryContainer: _surfaceSoftDark,
      onTertiaryContainer: _textDark,
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: _surfaceDark,
      onSurface: _textDark,
      surfaceContainerHighest: _lineDark,
      onSurfaceVariant: _mutedDark,
      outline: _lineDark,
      outlineVariant: _lineDark,
      shadow: Color(0xFF000000),
      scrim: Color(0x80000000),
      inverseSurface: _textDark,
      onInverseSurface: _textLight,
      inversePrimary: _brandLight,
      surfaceTint: _brandDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bgDark,
      appBarTheme: AppBarTheme(
        backgroundColor: _bgDark,
        foregroundColor: _textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: _surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _lineDark),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _brandDark,
          foregroundColor: _surfaceLight,
        ),
      ),
    );
  }
}
