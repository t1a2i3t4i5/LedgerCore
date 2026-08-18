import 'package:flutter/foundation.dart';

/// ログ 1 行の書き出し先。
///
/// [OperationLogger] はこの抽象だけを見る。おかげで Provider のテストは
/// 実ファイルを 1 つも作らずに [MemoryLogSink] を挿せるし、ロガーの初期化に
/// 失敗した端末では [NoopLogSink] へ倒せる。
///
/// **末尾の改行は実装側が付ける。** 呼び出し側が `'$line\n'` を組み立てると、
/// 行の区切りという JSON Lines の肝が実装ごとにばらける。
abstract class LogSink {
  /// [line] を 1 行として書き出す。
  ///
  /// 呼び出しは [OperationLogger] が直列化するので、実装は自前で
  /// 排他を持たなくてよい。
  Future<void> write(String line);
}

/// 何もしない [LogSink]。
///
/// ロガーの初期化に失敗した端末（書き込み先が取れない等）で使う。
/// ログが出ないことと引き換えにアプリは普通に起動する — 家計簿が使えなくなる
/// ほうが、ログが欠けることより重い。
class NoopLogSink implements LogSink {
  const NoopLogSink();

  @override
  Future<void> write(String line) async {}
}

/// 書かれた行をメモリに溜めるだけの [LogSink]。テスト専用。
///
/// 実ファイルを触らないので、Provider や画面のテストから気軽に挿せる。
@visibleForTesting
class MemoryLogSink implements LogSink {
  final List<String> lines = [];

  /// 次の [write] で投げる例外。ログの失敗がアプリの操作を壊さないことを
  /// 確かめるために使う
  Object? failWith;

  @override
  Future<void> write(String line) async {
    if (failWith != null) throw failWith!;
    lines.add(line);
  }
}
