import 'package:flutter/material.dart';

/// LedgerCore 固有の、[ColorScheme] に役割がない見た目の定数。
///
/// [subtext] は白いカード上で WCAG AA のコントラストを満たさないため、
/// 日付や補足ラベルなどの補助情報にだけ使う。本文サイズ以上の主要情報には
/// 使わない。
abstract final class LedgerTokens {
  static const subtext = Color(0xFFA39288);
  static const bodyMuted = Color(0xFF4A4038);
  static const barTrack = Color(0xFFEFE4D8);

  static const balancePositive = Color(0xFF5E8776);
  static const balancePositiveSurface = Color(0xFFE9F0EC);
  static const settlementSurface = Color(0xFFF5EEE5);
  static const balanceNegative = Color(0xFFC4633A);
  static const balanceEven = Color(0xFFA39288);

  static const cardRadius = 24.0;
  static const cardRadiusLarge = 28.0;
  static const pillRadius = 999.0;

  static const cardShadow = BoxShadow(
    color: Color.fromRGBO(120, 80, 50, 0.5),
    blurRadius: 26,
    offset: Offset(0, 10),
    spreadRadius: -18,
  );

  static const amountLarge = TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: ['ZenKakuGothicNew'],
    fontSize: 46,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.92,
  );
  static const amountRow = TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: ['ZenKakuGothicNew'],
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.40,
  );
  static const amountSmall = TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: ['ZenKakuGothicNew'],
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.28,
  );

  static const periodYear = TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: ['ZenKakuGothicNew'],
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.32,
  );
}
