import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'log_sink.dart';

/// 書き込み中のログファイル名
const kLogFileName = 'ledgercore.log';

/// 世代交代で退避する先のファイル名。**この 1 世代だけ残す**
const kRotatedLogFileName = 'ledgercore.1.log';

/// 1 ファイルの上限バイト数（1MB）。
///
/// 退避を 1 世代しか持たないので、端末が抱えるログは最大でもこの 2 倍。
/// **上限を変えるならここだけを直す。** 判定は [shouldRotate] が一手に見る
const kMaxLogFileBytes = 1024 * 1024;

/// これから [incomingBytes] を書き足すとき、先に世代交代すべきか。**純関数**。
///
/// 「現在サイズ + 追記ぶん」が上限を超えるなら交代する。書いた後に判定すると
/// 上限を必ず 1 行ぶん超えてから交代することになる。
///
/// [currentBytes] が 0 のときは交代しない。**1 行だけで上限を超える場合に
/// 効く。** 交代しても移した先が空になるだけで、その行は結局どこかに書かれる。
/// 判定を通すと「毎回 rename して毎回空ファイルに書く」形になり、行が 1 本ずつ
/// 別ファイルへ散ってすべて失われる
bool shouldRotate({
  required int currentBytes,
  required int incomingBytes,
  int maxBytes = kMaxLogFileBytes,
}) {
  if (currentBytes <= 0) return false;
  return currentBytes + incomingBytes > maxBytes;
}

/// ログをファイルへ追記する [LogSink]。
///
/// **書き込み先のディレクトリを引数で受け取る。** ここで
/// `getApplicationDocumentsDirectory()` を呼ばないのは、テストが
/// `Directory.systemTemp.createTemp()` を渡せるようにするため
/// （`path_provider` はプラグインなので素の `flutter test` では答えない）。
/// 実際のパス解決は `main.dart` の役目。
class FileLogSink implements LogSink {
  final Directory directory;

  /// 上限バイト数。テストから小さい値を入れて世代交代を確かめる
  final int maxBytes;

  FileLogSink(this.directory, {this.maxBytes = kMaxLogFileBytes});

  File get _file => File(p.join(directory.path, kLogFileName));
  File get _rotatedFile => File(p.join(directory.path, kRotatedLogFileName));

  @override
  Future<void> write(String line) async {
    // 上限はバイトで測る。日本語のカテゴリ名やメンバー名が入るので、
    // 文字数で数えると実際のファイルサイズが 3 倍近くまで膨らむ
    final data = utf8.encode('$line\n');
    final file = _file;

    final currentBytes = await file.exists() ? await file.length() : 0;
    if (shouldRotate(
      currentBytes: currentBytes,
      incomingBytes: data.length,
      maxBytes: maxBytes,
    )) {
      await _rotate(file);
    }

    // 追記の書き込みを 1 回で閉じる（IOSink を持ち回らない）。
    // 呼び出しは OperationLogger が直列化しているので競合しないし、
    // アプリがいつ落ちてもその時点までの行がファイルに残る
    await file.writeAsBytes(data, mode: FileMode.append, flush: true);
  }

  /// 現在のファイルを退避先へ移し、次の [write] に空のファイルを作らせる。
  ///
  /// 退避先が既にあれば消す。**残すのは 1 世代だけ**なので、`.2.log` へ
  /// ずらす連鎖は作らない
  Future<void> _rotate(File file) async {
    final rotated = _rotatedFile;
    if (await rotated.exists()) await rotated.delete();
    await file.rename(rotated.path);
  }
}
