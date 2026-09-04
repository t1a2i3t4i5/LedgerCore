import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/widgets/chart_palette.dart';

/// [foreground] を [background] の上に src-over で合成する。
/// labelColorOn が返す Colors.black87 はアルファ 0xDD の半透明で、
/// Color.computeLuminance() はアルファを無視するため、合成せずに比を取ると
/// 実際に描画されるより良い数値が出てしまう（teal で 7.00 対 6.19）。
Color _composite(Color foreground, Color background) {
  final a = foreground.a;
  int channel(double fg, double bg) => ((a * fg + (1 - a) * bg) * 255).round();
  return Color.fromARGB(
    255,
    channel(foreground.r, background.r),
    channel(foreground.g, background.g),
    channel(foreground.b, background.b),
  );
}

/// 実際に描画される色で見た WCAG 2.1 のコントラスト比。
/// 扇形に載せるラベルは 12px bold で「通常サイズ」扱いなので AA は 4.5:1。
double _effectiveContrastRatio(Color foreground, Color background) {
  final lf = _composite(foreground, background).computeLuminance();
  final lb = background.computeLuminance();
  final lighter = lf > lb ? lf : lb;
  final darker = lf > lb ? lb : lf;
  return (lighter + 0.05) / (darker + 0.05);
}

/// パレットは private なので、ID を十分な数だけ回して実際に使われる色を集める。
Set<Color> _allPaletteColors() => {
  for (var id = 0; id < 100; id++) categoryColor(id),
};

Set<Color> _allMemberPaletteColors() => {
  for (var id = 0; id < 100; id++) memberColor(id),
};

/// sRGB を CIE L*a*b*（D65）へ変換する。
/// パレットの色同士が知覚上近付き過ぎていないかを CIE76 ΔE で測る。
List<double> _lab(Color color) {
  double linearize(double channel) =>
      channel <= 0.04045
          ? channel / 12.92
          : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  final red = linearize(color.r);
  final green = linearize(color.g);
  final blue = linearize(color.b);
  final x = (red * 0.4124 + green * 0.3576 + blue * 0.1805) / 0.95047;
  final y = red * 0.2126 + green * 0.7152 + blue * 0.0722;
  final z = (red * 0.0193 + green * 0.1192 + blue * 0.9505) / 1.08883;

  double transform(double value) =>
      value > 0.008856
          ? math.pow(value, 1 / 3).toDouble()
          : 7.787 * value + 16 / 116;

  final fx = transform(x);
  final fy = transform(y);
  final fz = transform(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

double _deltaE(Color first, Color second) {
  final a = _lab(first);
  final b = _lab(second);
  return math.sqrt(
    math.pow(a[0] - b[0], 2) +
        math.pow(a[1] - b[1], 2) +
        math.pow(a[2] - b[2], 2),
  );
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('categoryColor', () {
    test('保存済みの色が ID 由来のフォールバックより優先される', () {
      final stored = categoryPalette.last;
      expect(categoryColor(1, colorValue: stored.toARGB32()), stored);
      expect(categoryColor(1), isNot(stored));
    });

    test('新規カテゴリの初期色は使用数が最少の色をパレット順で選ぶ', () {
      expect(leastUsedCategoryColor(const []), categoryPalette.first);
      expect(
        leastUsedCategoryColor([
          categoryPalette.first,
          categoryPalette.first,
          categoryPalette[1],
        ]),
        categoryPalette[2],
      );
      expect(leastUsedCategoryColor(categoryPalette), categoryPalette.first);
    });

    test('同じカテゴリ ID なら常に同じ色を返す', () {
      for (final id in [0, 1, 7, 42, 999]) {
        expect(categoryColor(id), categoryColor(id));
      }
    });

    test('既定カテゴリ 10 件（ID 1〜10）はすべて異なる色になる', () {
      final colors = [for (var id = 1; id <= 10; id++) categoryColor(id)];
      expect(colors.toSet().length, 10);
    });

    test('パレットの色数を超える ID でも例外なく色を循環させる', () {
      final colors = _allPaletteColors();
      expect(colors.length, 12);
      // 循環しているので、色数ぶん離れた ID は同じ色になる
      expect(categoryColor(3), categoryColor(3 + colors.length));
    });

    test('負の ID でも例外なく色を返す', () {
      // Dart の % は除数が正なら非負を返すので範囲外アクセスにならない
      expect(() => categoryColor(-1), returnsNormally);
      expect(() => categoryColor(-13), returnsNormally);
    });

    test('既定カテゴリ 1〜5 はデザイン案の色相を保った調整色になる', () {
      expect(
        [for (var id = 1; id <= 5; id++) categoryColor(id)],
        const [
          Color(0xFFB67049),
          Color(0xFFA57758),
          Color(0xFF957C6A),
          Color(0xFF7C8471),
          Color(0xFF807F95),
        ],
      );
    });

    test('パレット全色の CIE76 ΔE が 12 以上になる', () {
      final colors = _allPaletteColors().toList();
      for (var first = 0; first < colors.length; first++) {
        for (var second = first + 1; second < colors.length; second++) {
          final delta = _deltaE(colors[first], colors[second]);
          expect(
            delta,
            greaterThanOrEqualTo(12),
            reason:
                '${colors[first].toARGB32().toRadixString(16)} と '
                '${colors[second].toARGB32().toRadixString(16)} の ΔE が '
                '$delta しかない',
          );
        }
      }
    });

    test('画面背景・白いカード・帯のトラックに対して 3:1 以上になる', () {
      final backgrounds = [
        ledgerTheme.colorScheme.surface,
        ledgerTheme.colorScheme.surfaceContainerLowest,
        const Color(0xFFEFE4D8),
      ];
      for (final color in _allPaletteColors()) {
        for (final background in backgrounds) {
          final ratio = _contrastRatio(color, background);
          expect(
            ratio,
            greaterThanOrEqualTo(3),
            reason:
                '${color.toARGB32().toRadixString(16)} 対 '
                '${background.toARGB32().toRadixString(16)} の比が '
                '$ratio しかない',
          );
        }
      }
    });
  });

  group('memberColor', () {
    test('同じメンバー ID なら常に同じ色を返す', () {
      for (final id in [0, 1, 7, 42, 999]) {
        expect(memberColor(id), memberColor(id));
      }
    });

    test('パレットの色数を超える ID でも色を循環させる', () {
      final colors = _allMemberPaletteColors();
      expect(colors.length, 8);
      expect(memberColor(3), memberColor(3 + colors.length));
    });

    test('負の ID でも例外なく色を返す', () {
      expect(() => memberColor(-1), returnsNormally);
      expect(() => memberColor(-9), returnsNormally);
    });

    test('カテゴリ用パレットとは交わらない', () {
      expect(
        _allMemberPaletteColors().intersection(_allPaletteColors()),
        isEmpty,
      );
    });

    test('カテゴリ色とメンバー色の CIE76 ΔE が 12 以上になる', () {
      for (final category in _allPaletteColors()) {
        for (final member in _allMemberPaletteColors()) {
          final delta = _deltaE(category, member);
          expect(
            delta,
            greaterThanOrEqualTo(12),
            reason:
                '${category.toARGB32().toRadixString(16)} と '
                '${member.toARGB32().toRadixString(16)} の ΔE が '
                '$delta しかない',
          );
        }
      }
    });
  });

  group('labelColorOn', () {
    test('パレット全色で実効コントラスト比が WCAG AA（4.5:1）以上になる', () {
      for (final color in _allPaletteColors()) {
        final ratio = _effectiveContrastRatio(labelColorOn(color), color);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '色 ${color.toARGB32().toRadixString(16)} の比が $ratio しかない',
        );
      }
    });

    test('白と黒のうち実効コントラストが高い側を選ぶ', () {
      for (final color in _allPaletteColors()) {
        final chosen = labelColorOn(color);
        final other = chosen == Colors.white ? Colors.black87 : Colors.white;
        expect(
          _effectiveContrastRatio(chosen, color),
          greaterThanOrEqualTo(_effectiveContrastRatio(other, color)),
          reason: '色 ${color.toARGB32().toRadixString(16)} で読みにくい側を選んでいる',
        );
      }
    });

    test('明るい背景には黒、暗い背景には白を返す', () {
      expect(labelColorOn(Colors.white), Colors.black87);
      expect(labelColorOn(Colors.black), Colors.white);
    });
  });

  group('trendColor', () {
    // 推移グラフのツールチップは trendColor を背景に敷いて文字を載せるので、
    // 棒の色が変わったときに文字が読めなくなる経路も各テーマで塞ぐ。
    test('アプリのライトテーマで primary と文字の AA を保つ', () {
      final scheme = ledgerTheme.colorScheme;
      final bar = trendColor(scheme);
      expect(bar, scheme.primary);
      expect(
        _effectiveContrastRatio(labelColorOn(bar), bar),
        greaterThanOrEqualTo(4.5),
      );
    });

    // アプリはライト専用だが、固定色を直書きして将来のダークテーマで
    // ツールチップの文字が背景に溶ける回帰は合成スキームで守る。
    test('合成ダークスキームで primary と文字の AA を保つ', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E2620),
        brightness: Brightness.dark,
      );
      final bar = trendColor(scheme);
      expect(bar, scheme.primary);
      expect(
        _effectiveContrastRatio(labelColorOn(bar), bar),
        greaterThanOrEqualTo(4.5),
      );
    });

    // カテゴリの色を流用すると、無関係なカテゴリと同色になって
    // 「この棒は食費」という誤った対応に見える
    test('ライトテーマでカテゴリ色をそのまま流用していない', () {
      expect(
        _allPaletteColors(),
        isNot(contains(trendColor(ledgerTheme.colorScheme))),
      );
    });
  });
}
