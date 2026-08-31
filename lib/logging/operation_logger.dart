import 'package:flutter/foundation.dart';

import 'log_entry.dart';
import 'log_sink.dart';

/// 「今」を返す関数。既定は [DateTime.now] で、テストから固定時刻を注入する口。
///
/// `providers/month_scoped_provider.dart` の `Clock` を import しないのは、
/// ログ層が Provider 層を参照すると「画面 → providers → AppDatabase」の
/// 一方向にログだけ逆流の枝が生えるため。
///
/// **名前をずらしてあるのは意図的。** 同じ `Clock` にすると、両方を import
/// するファイル（`main.dart` や Provider のテスト）が毎回 `hide` を書く羽目に
/// なる。typedef は型の別名でしかないので、名前が違っても実体はどちらも
/// `DateTime Function()` で、同じ関数をそのまま両方へ渡せる。
typedef LogClock = DateTime Function();

/// 操作ログの入口。呼び出し側が触る唯一の型。
///
/// [LogSink] と [LogClock] を注入で受け取る（`AppDatabase` を注入で受け取る
/// Provider と同じ形）。ログ層は `AppDatabase` も Provider も参照しない。
///
/// ## なぜ [info] / [error] が `void` なのか
///
/// ファイルへの追記は非同期だが、**呼び出し側に await させない。**
/// `create()` の中で `await logger.info(...)` を書くと、取引の保存が
/// ファイル I/O を待つぶんだけ遅くなる。ログのために操作の応答を落とすのは
/// 順序が逆。
///
/// 代わりに [info] / [error] は行の組み立てまでを**同期で**済ませ
/// （時刻の確定を含む）、書き出しを内部のキューへ積んで即座に戻る。
/// キューは単一の [Future] チェーンなので、**呼んだ順にファイルへ並ぶ**。
/// 各呼び出しが独立に `write` を始める形だと、行の順序が I/O の完了順に
/// 化けて「削除のあとに追加」が記録される。
///
/// テストは [flush] でキューの消化を待てる。
class OperationLogger {
  final LogSink _sink;
  final LogClock _clock;

  /// 書き出しの直列化に使う。1 つ前の書き出しを待ってから次を書くので、
  /// ここに繋いだ順がそのままファイルの行順になる。
  ///
  /// **初期値を `Future.value()` にしない。** コンストラクタが走った時点の
  /// ゾーンに属する `Future` を起点にすると、そこへ繋いだコールバックも
  /// そのゾーンで動く。`setUp` でロガーを作って `testWidgets` の中で
  /// `info()` を呼ぶと、書き出しが擬似時間のゾーンから流れなくなり、
  /// `pump` しても行が 1 つも書かれない。null から始めて、最初の
  /// [_enqueue] を呼んだゾーンでチェーンを起こす
  Future<void>? _pending;

  OperationLogger(this._sink, {LogClock? clock})
    : _clock = clock ?? DateTime.now;

  /// 何もどこにも書かないロガー。ロガーの初期化に失敗した端末や、
  /// ログを見ないテストの既定値に使う
  factory OperationLogger.noop() => OperationLogger(const NoopLogSink());

  /// 操作が起きたことを記録する
  void info(String op, {Map<String, Object?> detail = const {}}) {
    _enqueue(LogLevel.info, op, detail, null);
  }

  /// 操作が失敗したことを [error] つきで記録する
  void error(
    String op,
    Object error, {
    Map<String, Object?> detail = const {},
  }) {
    _enqueue(LogLevel.error, op, detail, error);
  }

  /// 積まれた書き出しがすべて済むまで待つ。
  ///
  /// production では呼ばない（呼ぶと [info] を `void` にした意味がなくなる）。
  /// ログの中身を確かめるテストが、書き出しの完了を待つための口
  Future<void> flush() async => _pending;

  /// 先行する書き込み後に読み出しを行い、その間の追記・世代交代を待たせる。
  /// 共有シートの待機はこの中へ含めない。失敗しても後続の書き込みは再開する。
  Future<T> withPausedWrites<T>(Future<T> Function() read) {
    final previous = _pending;
    final result = () async {
      if (previous != null) await previous;
      return read();
    }();
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  void _enqueue(
    LogLevel lv,
    String op,
    Map<String, Object?> detail,
    Object? error,
  ) {
    final String line;
    try {
      // 時刻はここで確定させる。キューを消化する時点で読むと、書き込みが
      // 詰まったぶんだけ実際の操作時刻から後ろへずれる
      line = toJsonLine(
        LogEntry(
          ts: _clock(),
          lv: lv,
          op: op,
          detail: detail,
          // toString() をそのまま載せない。DB の例外はバインド値（取引のメモを
          // 含む）を文字列に並べるので、sanitizeError で伏せてから渡す
          error: error == null ? null : sanitizeError(error),
        ),
      );
    } catch (e) {
      // 組み立てに失敗した 1 行はあきらめる。ログのために操作を壊さない
      debugPrint('OperationLogger: ログ行の組み立てに失敗 op=$op: $e');
      return;
    }

    final previous = _pending;
    _pending = () async {
      // 1 つ前の書き出しを待ってから書く。各呼び出しが独立に write を始めると、
      // 行の順序が I/O の完了順に化けて「削除のあとに追加」が記録される
      if (previous != null) await previous;
      try {
        await _sink.write(line);
      } catch (e) {
        // **意図的な握りつぶし。** ここで例外を通すと、書き込み先が
        // 埋まった端末で家計簿そのものが操作不能になる。ログが欠けるほうが
        // 軽い。気付けるようコンソールには落とす
        debugPrint('OperationLogger: ログの書き込みに失敗 op=$op: $e');
      }
    }();
  }
}
