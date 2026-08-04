import 'package:flutter/material.dart';

/// グラフ用の固定パレット。
/// 既定カテゴリは 10 件なので、12 色あれば通常は色が重複しない。
const List<Color> _palette = [
  Color(0xFF26A69A), // teal 400
  Color(0xFFEF5350), // red 400
  Color(0xFF42A5F5), // blue 400
  Color(0xFFFFA726), // orange 400
  Color(0xFFAB47BC), // purple 400
  Color(0xFF66BB6A), // green 400
  Color(0xFFEC407A), // pink 400
  Color(0xFF29B6F6), // light blue 400
  Color(0xFF8D6E63), // brown 400
  Color(0xFFFFCA28), // amber 400
  Color(0xFF5C6BC0), // indigo 400
  Color(0xFF9CCC65), // light green 400
];

/// カテゴリ ID から色を決定的に選ぶ。
/// 同じカテゴリは常に同じ色になるので、グラフ・凡例・リストの対応が崩れない。
Color categoryColor(int categoryId) => _palette[categoryId % _palette.length];

/// [background] の上に載せる文字色を返す。
/// 塗り色の明るさで白／黒を切り替え、テーマに依らずコントラストを確保する。
Color labelColorOn(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
