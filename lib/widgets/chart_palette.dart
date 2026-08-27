import 'package:flutter/material.dart';

/// カテゴリを識別するための固定パレット。
/// 既定カテゴリは 10 件なので、12 色あれば通常は色が重複しない。
const List<Color> _palette = [
  Color(0xFF3D7F78), // 青緑
  Color(0xFFB67049), // デザイン案の橙を背景上で識別できる明度へ調整
  Color(0xFFA57758), // デザイン案の薄橙を背景上で識別できる明度へ調整
  Color(0xFF957C6A), // デザイン案の茶を背景上で識別できる明度へ調整
  Color(0xFF7C8471), // デザイン案の緑を背景上で識別できる明度へ調整
  Color(0xFF807F95), // デザイン案の紫を背景上で識別できる明度へ調整
  Color(0xFF3F7196), // 青
  Color(0xFF71658F), // 青紫
  Color(0xFF8E5E7C), // 赤紫
  Color(0xFFA45555), // 赤
  Color(0xFF88713D), // 黄土
  Color(0xFF63783F), // オリーブ
];

/// メンバーを識別するための固定パレット。
/// カテゴリとの無意味な対応を作らないよう、カテゴリ用とは別の色だけを持つ。
const List<Color> _memberPalette = [
  Color(0xFFE8A87C), // デザイン案（みく）
  Color(0xFF8FB8A8), // デザイン案（たいち）
  Color(0xFFD39B84), // コーラル
  Color(0xFF829FBA), // ブルー
  Color(0xFFB29ABF), // ラベンダー
  Color(0xFFC69AA8), // ローズ
  Color(0xFFA8AF7A), // オリーブ
  Color(0xFF7FAEAA), // ティール
];

/// カテゴリ ID から色を決定的に選ぶ。
/// 同じカテゴリは常に同じ色になるので、グラフ・凡例・リストの対応が崩れない。
Color categoryColor(int categoryId) => _palette[categoryId % _palette.length];

/// メンバー ID から色を決定的に選ぶ。
/// カテゴリ色とは交わらないため、同色による無意味な対応が生まれない。
Color memberColor(int memberId) =>
    _memberPalette[memberId % _memberPalette.length];

/// 白と黒のどちらが読みやすいかが入れ替わる輝度。
/// 白との比 (1.05)/(L+0.05) と黒との比 (L+0.05)/0.05 が等しくなる点で、
/// L = sqrt(0.0525) - 0.05 ≒ 0.179。
/// 0.5 を境にすると中間色（teal・orange など）で読みにくい側を選んでしまう。
const double _labelLuminanceThreshold = 0.179;

/// [background] の上に載せる文字色を返す。
/// 塗り色の明るさで白／黒を切り替え、テーマに依らずコントラストを確保する。
Color labelColorOn(Color background) =>
    background.computeLuminance() > _labelLuminanceThreshold
        ? const Color(0xDD000000)
        : const Color(0xFFFFFFFF);

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
