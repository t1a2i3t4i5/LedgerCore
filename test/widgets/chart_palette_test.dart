import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/widgets/chart_palette.dart';

/// WCAG 2.1 のコントラスト比。扇形に載せるラベルは 12px bold で
/// 「通常サイズ」扱いなので AA は 4.5:1 を要求する。
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
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
    test('パレット全色でコントラスト比が WCAG AA（4.5:1）以上になる', () {
      for (final color in _allPaletteColors()) {
        final ratio = _contrastRatio(color, labelColorOn(color));
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '色 ${color.toARGB32().toRadixString(16)} の比が $ratio しかない',
        );
      }
    });

    test('白と黒のうちコントラストが高い側を選ぶ', () {
      for (final color in _allPaletteColors()) {
        final chosen = labelColorOn(color);
        final other = chosen == Colors.white ? Colors.black87 : Colors.white;
        expect(
          _contrastRatio(color, chosen),
          greaterThanOrEqualTo(_contrastRatio(color, other)),
          reason: '色 ${color.toARGB32().toRadixString(16)} で読みにくい側を選んでいる',
        );
      }
    });

    test('明るい背景には黒、暗い背景には白を返す', () {
      expect(labelColorOn(Colors.white), Colors.black87);
      expect(labelColorOn(Colors.black), Colors.white);
    });
  });
}
