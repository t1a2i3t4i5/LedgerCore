import 'package:flutter/material.dart';

import 'ledger_tokens.dart';

final _ledgerColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF2E2620),
).copyWith(
  primary: const Color(0xFF2E2620),
  onPrimary: const Color(0xFFFBF6F0),
  primaryContainer: const Color(0xFFF2E7DC),
  onPrimaryContainer: const Color(0xFF2E2620),
  secondary: const Color(0xFFE08A5A),
  onSecondary: const Color(0xFFFFFFFF),
  secondaryContainer: const Color(0xFFFDEEE4),
  onSecondaryContainer: const Color(0xFFC4633A),
  surface: const Color(0xFFFBF6F0),
  onSurface: const Color(0xFF2E2620),
  surfaceContainerLowest: const Color(0xFFFFFFFF),
  surfaceContainerLow: const Color(0xFFFFFFFF),
  surfaceContainerHighest: const Color(0xFFF2E7DC),
  onSurfaceVariant: const Color(0xFF7A6656),
  outlineVariant: const Color(0xFFF3EDE6),
  surfaceTint: Colors.transparent,
  error: const Color(0xFFB3443A),
  onError: const Color(0xFFFFFFFF),
  errorContainer: const Color(0xFFF7DED8),
  onErrorContainer: const Color(0xFF7A2A22),
);

final _baseTheme = ThemeData(
  useMaterial3: true,
  colorScheme: _ledgerColorScheme,
  fontFamily: 'ZenMaruGothic',
);

const _headingStyle = TextStyle(
  fontFamily: 'ZenKakuGothicNew',
  fontWeight: FontWeight.w700,
);

/// ライトモード専用のアプリテーマ。
final ledgerTheme = _baseTheme.copyWith(
  scaffoldBackgroundColor: _ledgerColorScheme.surface,
  textTheme: _baseTheme.textTheme.copyWith(
    titleSmall: _baseTheme.textTheme.titleSmall?.merge(_headingStyle),
    titleMedium: _baseTheme.textTheme.titleMedium?.merge(_headingStyle),
    titleLarge: _baseTheme.textTheme.titleLarge?.merge(_headingStyle),
    headlineSmall: _baseTheme.textTheme.headlineSmall?.merge(_headingStyle),
    headlineMedium: _baseTheme.textTheme.headlineMedium?.merge(_headingStyle),
    headlineLarge: _baseTheme.textTheme.headlineLarge?.merge(_headingStyle),
    displaySmall: _baseTheme.textTheme.displaySmall?.merge(_headingStyle),
    displayMedium: _baseTheme.textTheme.displayMedium?.merge(_headingStyle),
    displayLarge: _baseTheme.textTheme.displayLarge?.merge(_headingStyle),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: _ledgerColorScheme.surface,
    foregroundColor: _ledgerColorScheme.onSurface,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
  ),
  cardTheme: CardThemeData(
    color: _ledgerColorScheme.surfaceContainerLow,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LedgerTokens.cardRadius),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: _ledgerColorScheme.surfaceContainerLow,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LedgerTokens.cardRadius),
    ),
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: _ledgerColorScheme.surfaceContainerLow,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(LedgerTokens.cardRadiusLarge),
      ),
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: _ledgerColorScheme.surfaceContainerHighest,
    selectedColor: _ledgerColorScheme.secondaryContainer,
    showCheckmark: false,
    side: WidgetStateBorderSide.resolveWith(
      (states) =>
          states.contains(WidgetState.selected)
              ? BorderSide(color: _ledgerColorScheme.onSurface, width: 2)
              : BorderSide.none,
    ),
    shape: const StadiumBorder(),
    labelStyle: _baseTheme.textTheme.labelLarge!.copyWith(
      color: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? _ledgerColorScheme.onSurface
                : _ledgerColorScheme.onPrimaryContainer,
      ),
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: _ledgerColorScheme.primary,
    foregroundColor: _ledgerColorScheme.onPrimary,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: _ledgerColorScheme.onSurface,
    contentTextStyle: TextStyle(color: _ledgerColorScheme.surface),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LedgerTokens.cardRadius),
    ),
  ),
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? _ledgerColorScheme.surfaceContainerLowest
                : _ledgerColorScheme.primaryContainer,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? _ledgerColorScheme.onSurface
                : _ledgerColorScheme.onPrimaryContainer,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: _ledgerColorScheme.outlineVariant),
      ),
    ),
  ),
);
