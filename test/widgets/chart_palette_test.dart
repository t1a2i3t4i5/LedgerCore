import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/widgets/chart_palette.dart';

/// [foreground] を [background] の上に src-over で合成する。
/// labelColorOn が返す Colors.black87 はアルファ 0xDD の半透明で、
/// Color.computeLuminance() はアルファを無視するため、合成せずに比を取ると
/// 実際に描画されるより良い数値が出てしまう（teal で 7.00 対 6.19）。
Color _composite(Color foreground, Color background) {
  final a = foreground.a;
  int channel(double fg, double bg) =>
      ((a * fg + (1 - a) * bg) * 255).round();
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
Set<Color> _allPaletteColors() =>
    {for (var id = 0; id < 100; id++) categoryColor(id)};

void main() {
  group('categoryColor', () {
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
    // main.dart の ThemeData(colorSchemeSeed: Colors.teal) と同じ採り方をする。
    // 推移グラフのツールチップは trendColor を背景に敷いて文字を載せるので、
    // 棒の色が変わったときに文字が読めなくなる経路がここで塞がる
    ColorScheme scheme(Brightness brightness) =>
        ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness);

    test('ライト・ダークとも ColorScheme の primary を返す', () {
      for (final brightness in Brightness.values) {
        final s = scheme(brightness);
        expect(trendColor(s), s.primary, reason: '$brightness');
      }
    });

    // ダークテーマでは primary が明るい側へ反転するので、固定色を直書きすると
    // ここが落ちる（ツールチップの文字が背景に溶ける）
    test('ツールチップの文字が実効コントラスト AA（4.5:1）を満たす', () {
      for (final brightness in Brightness.values) {
        final bar = trendColor(scheme(brightness));
        final ratio = _effectiveContrastRatio(labelColorOn(bar), bar);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$brightness で $ratio');
      }
    });

    // カテゴリの色を流用すると、無関係なカテゴリと同色になって
    // 「この棒は食費」という誤った対応に見える
    test('ライトテーマでカテゴリ色をそのまま流用していない', () {
      expect(_allPaletteColors(), isNot(contains(trendColor(scheme(Brightness.light)))));
    });
  });
}
