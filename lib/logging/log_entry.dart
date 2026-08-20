import 'dart:convert';

import 'package:flutter/foundation.dart';

/// ログの重大度。
///
/// **この 2 値だけにする。** `debug` / `warn` を足すと「どちらで出すか」の
/// 判断が呼び出し側 20 箇所以上に散り、実際には全部 `info` になる。
/// 「操作が起きた」か「失敗した」かの 2 択で足りる。
enum LogLevel { info, error }

/// `error` に載せる例外文字列の上限（文字数）。
///
/// drift の `SqliteException` はスタックトレース混じりで数 KB になることがある。
/// 1 行が長くなるとローテーションが実質的にその 1 行で起きてしまうので頭を残して切る。
const kMaxErrorLength = 1000;

/// ログ 1 行ぶんのデータ。
///
/// **このクラスも [toJsonLine] も I/O を持たない。** ファイルにも DB にも触らず、
/// 値を受け取って文字列を返すだけ（`db/summary_calculator.dart` と同じ位置づけ）。
/// おかげで書式の検証はファイルを 1 つも作らずに書ける。
@immutable
class LogEntry {
  /// 記録時刻。`DateTime.now()` を読まず、[OperationLogger] に注入された
  /// `Clock` から受け取る（テストで固定するため）
  final DateTime ts;

  final LogLevel lv;

  /// `<対象>.<動作>` のドット区切り。`transaction.create` など
  final String op;

  /// op ごとの付随情報。**op ごとにキーを固定する。**
  /// 値が `null` のキーは出力から落ちる
  final Map<String, Object?> detail;

  /// [LogLevel.error] のときだけ載る例外の文字列
  final String? error;

  const LogEntry({
    required this.ts,
    required this.lv,
    required this.op,
    this.detail = const {},
    this.error,
  });
}

/// [entry] を JSON Lines の 1 行へ変換する（末尾に改行は付けない）。**純関数**。
///
/// キーの順は `ts` → `lv` → `op` → `detail` → `error` で固定。Dart の `Map` は
/// 挿入順を保つので、この関数が組み立てた順がそのまま出力になる。
/// 目で追うログなので、行ごとに列が動かないことに意味がある。
String toJsonLine(LogEntry entry) {
  final map = <String, Object?>{
    'ts': formatLogTimestamp(entry.ts),
    'lv': entry.lv.name,
    'op': entry.op,
  };

  // 値が null のキーは落とす。「無い」ことを "detail":{"id":null} と書いても
  // 読む側の情報が増えない
  final detail = <String, Object?>{};
  entry.detail.forEach((key, value) {
    if (value == null) return;
    detail[key] = _normalize(value);
  });
  if (detail.isNotEmpty) map['detail'] = detail;

  // error は lv が error のときだけ。info の行に空の error 列を作らない
  if (entry.lv == LogLevel.error && entry.error != null) {
    map['error'] = _truncate(entry.error!);
  }

  // jsonEncode が改行・引用符・制御文字をエスケープするので、
  // 例外メッセージが複数行でも 1 行に収まる（JSON Lines の前提）
  return jsonEncode(map);
}

/// ログの時刻書式。ローカル時刻の ISO8601 で **ミリ秒までに固定する**。
///
/// `DateTime.toIso8601String()` を使わないのは、マイクロ秒が 0 かどうかで
/// 小数部が 3 桁になったり 6 桁になったりするため。行ごとに幅が変わると
/// 目で追いづらく、テストの期待値も書けない。
String formatLogTimestamp(DateTime ts) {
  final t = ts.toLocal();
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  return '${pad(t.year, 4)}-${pad(t.month, 2)}-${pad(t.day, 2)}'
      'T${pad(t.hour, 2)}:${pad(t.minute, 2)}:${pad(t.second, 2)}'
      '.${pad(t.millisecond, 3)}';
}

/// `detail` の値を `jsonEncode` が扱える形へ均す。
///
/// ここを通さないと `jsonEncode` が実行時に落ちる。しかもログの書き込み例外は
/// 握りつぶす設計（[OperationLogger] 参照）なので、**落ちたことに誰も気付かず
/// その行だけ静かに消える**。呼び出し側 20 箇所に「String にしてから渡す」を
/// 守らせるより、受け取る側で均すほうが確実。
///
/// - `DateTime` → 時刻書式（フィルターの日付や `spentAt` が該当）
/// - `Set` / `Iterable` → `List`（`jsonEncode` は `Set` を書けない。
///   `TransactionProvider` のフィルターが `Set<int>` を持つ）
/// - `Enum` → 名前（`SummaryPeriod` や `SortOrder` が該当）
///
/// [depth] が [_maxNormalizeDepth] を超えたら、そこから先は `toString()` で
/// 畳む。**入れ子が深すぎる値や循環参照でこの関数が自分自身を呼び続けるのを
/// 止めるため。** 止めないと `StackOverflowError` になり、`OperationLogger` が
/// その行を捨てる（`StackOverflowError` を捕まえてからの復帰は当てにできない）。
/// 畳んだ文字列でも「何が入っていたか」は残るので、行ごと消えるよりましになる。
Object? _normalize(Object? value, [int depth = 0]) {
  if (value == null) return null;
  if (value is DateTime) return formatLogTimestamp(value);
  if (value is Enum) return value.name;
  if (value is num || value is bool || value is String) return value;
  if (depth >= _maxNormalizeDepth) return value.toString();
  if (value is Map) {
    return value.map(
      (k, v) => MapEntry(k.toString(), _normalize(v, depth + 1)),
    );
  }
  if (value is Iterable) {
    return value.map((e) => _normalize(e, depth + 1)).toList();
  }
  return value.toString();
}

/// `detail` の入れ子をたどる深さの上限。
///
/// 実際の `detail` は 1〜2 段しかないので、これに当たるのは想定外の値が
/// 紛れ込んだときだけ
const _maxNormalizeDepth = 8;

String _truncate(String text) =>
    text.length <= kMaxErrorLength
        ? text
        : '${text.substring(0, kMaxErrorLength)}…';

/// 例外の文字列から、DB へ渡した値が混ざる部分だけを伏せる。**純関数**。
///
/// `sqlite3` の `SqliteException.toString()` は失敗した文に続けて
/// `, parameters: 1, 1, 0.0, ..., ひみつの通院, ...` とバインド値を全部並べる。
/// 取引のメモもそこに入るので、[LogEntry.detail] から本文を外して
/// `memoLength` だけにしても、**同じ行の `error` 経由でメモ本文がログファイルへ
/// 残ってしまう**（`detail` に `memoLength:6` と本文が並ぶ）。
/// ログファイルは端末外へ持ち出されうる、というのがこの設計の前提なので、
/// 守りたかったものがそのまま抜けていた。
///
/// 落とすのは値が並ぶ `, parameters:` から**その行の終わりまで**に限る。
/// `Causing statement:` の文そのものはプレースホルダ（`VALUES (?, ?, ...)`）
/// しか含まないので残す — どの文で落ちたかは失敗の追跡に要る。行末で止めるのは、
/// `main.dart` の `app.uncaught` が例外の後ろにスタックトレースを繋げて
/// 渡してくるため。例外以降を丸ごと捨てるとスタックまで消える。
///
/// 例外の型で判定せず文字列で見るのは、`sqlite3` が推移的依存で、
/// `test/matchers.dart` が文言で判定しているのと同じ理由。
String sanitizeError(Object error) => error.toString().replaceAll(
  RegExp(r', parameters: [^\n]*'),
  ', parameters: <省略>',
);
