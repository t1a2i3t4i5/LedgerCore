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

/// 白と黒のどちらが読みやすいかが入れ替わる輝度。
/// 白との比 (1.05)/(L+0.05) と黒との比 (L+0.05)/0.05 が等しくなる点で、
/// L = sqrt(0.0525) - 0.05 ≒ 0.179。
/// 0.5 を境にすると中間色（teal・orange など）で読みにくい側を選んでしまう。
const double _labelLuminanceThreshold = 0.179;

/// [background] の上に載せる文字色を返す。
/// 塗り色の明るさで白／黒を切り替え、テーマに依らずコントラストを確保する。
Color labelColorOn(Color background) =>
    background.computeLuminance() > _labelLuminanceThreshold
        ? Colors.black87
        : Colors.white;

/// 推移グラフ（`widgets/period_bar_chart.dart`）の棒の色。
///
/// [categoryColor] を流用しないこと。あれはカテゴリ ID から色を選ぶ関数なので、
/// カテゴリと対応しない棒に使うと「食費と同じ色」という無意味な結び付きが
/// 画面上に生まれ、意味のある対応に見えてしまう。
///
/// 固定色を直書きせず [ColorScheme] に委ねるのは、推移グラフの棒が
/// 「その画面の主役の 1 色」でしかなく、カテゴリのように**互いを区別する**
/// 必要が無いため。テーマから採ればダークテーマでもコントラストが保たれる。
Color trendColor(ColorScheme scheme) => scheme.primary;
