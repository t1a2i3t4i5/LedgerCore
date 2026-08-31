import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 同梱フォントの構成を `pubspec.yaml` と `assets/fonts/` の実体で守る。
///
/// ウィジェットテストは同梱フォントを読み込まないので（docs/testing.md）、
/// 「宣言したファイルが無い」「使わないウェイトが残っている」は通常の描画検証では
/// 捕まらない。ここではファイルシステムの側から確かめる。
void main() {
  final fontsDir = Directory('assets/fonts');

  /// `pubspec.yaml` の `fonts:` 節に現れる `asset:` のパスを、書かれた順に返す。
  ///
  /// yaml パーサは依存に無いので、`asset:` の行だけを拾う。`fonts:` 節の外に
  /// `asset:` が現れる書き方はこのファイルには無い。
  List<String> declaredFontAssets() {
    return File('pubspec.yaml')
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.startsWith('- asset:'))
        .map((line) => line.substring('- asset:'.length).trim())
        .toList();
  }

  test('宣言した ttf と assets/fonts の ttf が 1 対 1 で対応する', () {
    final declared = declaredFontAssets()..sort();
    final onDisk =
        fontsDir
            .listSync()
            .map((e) => e.path)
            .where((path) => path.endsWith('.ttf'))
            .toList()
          ..sort();

    expect(declared, onDisk);
  });

  test('本文書体は Regular だけを同梱する', () {
    // 太字は ZenKakuGothicNew に一本化してある（LedgerTokens.heading）。
    // Zen Maru Gothic の Bold を戻すと 3.60MiB 太るので、宣言の側で止める
    expect(
      declaredFontAssets().where((path) => path.contains('ZenMaruGothic')),
      ['assets/fonts/ZenMaruGothic-Regular.ttf'],
    );
  });

  test('同梱 ttf の合計サイズが予算に収まる', () {
    // #106 の削減後は 5.94MiB。日本語フォントのウェイト追加による
    // 再肥大化を検出するため、7MiB 未満を予算にする
    const budgetBytes = 7 * 1024 * 1024;
    final total = fontsDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.ttf'))
        .fold<int>(0, (sum, file) => sum + file.lengthSync());

    expect(total, lessThan(budgetBytes));
  });
}
