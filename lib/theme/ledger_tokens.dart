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
  static const countSurface = Color(0xFFF2F1ED);
  // secondaryContainer上で小さな先月比ラベルも読める濃さにする。
  static const comparisonText = Color(0xFFA65330);

  static const balancePositive = Color(0xFF5E8776);
  static const balancePositiveSurface = Color(0xFFE9F0EC);
  static const settlementSurface = Color(0xFFF5EEE5);
  static const balanceNegative = Color(0xFFC4633A);
  static const balanceEven = Color(0xFFA39288);

  // 「カテゴリを追加」の破線枠。ColorScheme の outlineVariant（#F3EDE6）は
  // カード同士の区切り線用の淡さで、背景 #FBF6F0 の上に置く枠には弱すぎる。
  static const dashedOutline = Color(0xFFD9CCBE);

  static const cardRadius = 24.0;
  static const cardRadiusLarge = 28.0;
  static const pillRadius = 999.0;

  static const cardShadow = BoxShadow(
    color: Color.fromRGBO(120, 80, 50, 0.5),
    blurRadius: 26,
    offset: Offset(0, 10),
    spreadRadius: -18,
  );

  /// 見出しと強調に使う書体。
  ///
  /// 本文の Zen Maru Gothic は Regular だけを同梱するため、太字にしたい箇所は
  /// `fontWeight` だけを上げず、この書体へ切り替える。同梱していないウェイトの
  /// 代替描画に強調を任せない（#106）。
  static const heading = TextStyle(
    fontFamily: 'ZenKakuGothicNew',
    fontWeight: FontWeight.w700,
  );

  static const amountLarge = TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: ['ZenKakuGothicNew'],
    fontSize: 46,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.92,
  );
  static const amountCurrency = TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: ['ZenKakuGothicNew'],
    fontSize: 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.52,
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
