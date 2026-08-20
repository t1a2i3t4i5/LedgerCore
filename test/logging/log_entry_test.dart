import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/logging/log_entry.dart';

/// ログ 1 行の書式を確かめる。
///
/// [toJsonLine] は I/O を持たない純関数なので、ここではファイルも DB も作らない
/// （`summary_calculator_test.dart` と同じ立て付け）。
///
/// 出来上がった文字列そのものを期待値に置くのは、**キーの順まで固定したい**ため。
/// `jsonDecode` して Map で比べると順が入れ替わっても通ってしまい、行ごとに列が
/// 動くログになる。目で追う前提の形式なのでそこを守る。
void main() {
  final ts = DateTime(2026, 8, 17, 14, 3, 22, 481);

  group('toJsonLine', () {
    test('キーは ts → lv → op → detail → error の順で並ぶ', () {
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.error,
        op: 'transaction.delete',
        detail: const {'id': 42},
        error: 'SqliteException(787)',
      ));

      expect(
        line,
        '{"ts":"2026-08-17T14:03:22.481","lv":"error",'
        '"op":"transaction.delete","detail":{"id":42},'
        '"error":"SqliteException(787)"}',
      );
    });

    test('detail の null は キーごと落ちる', () {
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.info,
        op: 'transaction.create',
        // メモ無しの取引は memoLength が null になる
        detail: const {'amount': 1200.0, 'memoLength': null},
      ));

      expect(line, contains('"amount":1200.0'));
      expect(line, isNot(contains('memoLength')));
    });

    test('detail が空なら detail キーごと出ない', () {
      final line = toJsonLine(
        LogEntry(ts: ts, lv: LogLevel.info, op: 'transaction.filter.reset'),
      );

      expect(
        line,
        '{"ts":"2026-08-17T14:03:22.481","lv":"info",'
        '"op":"transaction.filter.reset"}',
      );
    });

    test('中身が全部 null の detail も detail キーごと出ない', () {
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.info,
        op: 'transaction.create',
        detail: const {'memoLength': null},
      ));

      expect(line, isNot(contains('detail')));
    });

    test('lv が info なら error は載らない', () {
      // 呼び出し側が誤って error を渡しても、info の行に error 列を作らない
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.info,
        op: 'transaction.create',
        error: '握りつぶされるべき',
      ));

      expect(line, isNot(contains('error')));
    });

    test('長すぎる error は頭を残して切る', () {
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.error,
        op: 'app.uncaught',
        error: 'あ' * (kMaxErrorLength + 500),
      ));

      // 1 行が長大になるとローテーションがその 1 行で起きてしまう
      expect(line.contains('あ' * kMaxErrorLength), isTrue);
      expect(line.contains('あ' * (kMaxErrorLength + 1)), isFalse);
      expect(line, contains('…'));
    });

    test('ちょうど上限の error は切らない', () {
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.error,
        op: 'app.uncaught',
        error: 'あ' * kMaxErrorLength,
      ));

      expect(line, isNot(contains('…')));
    });
  });

  group('detail の値の均し', () {
    test('Set は List になる', () {
      // TransactionProvider のフィルターが Set<int> を持つ。
      // 均さないと jsonEncode が実行時に落ち、その行が静かに消える
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.info,
        op: 'transaction.filter',
        detail: const {
          'categoryIds': {3, 1}
        },
      ));

      expect(line, contains('"categoryIds":[3,1]'));
    });

    test('DateTime は時刻の書式になる', () {
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.info,
        op: 'transaction.create',
        detail: {'spentAt': DateTime(2026, 7, 10)},
      ));

      expect(line, contains('"spentAt":"2026-07-10T00:00:00.000"'));
    });

    test('enum は名前になる', () {
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.info,
        op: 'transaction.sort',
        detail: const {'order': LogLevel.error},
      ));

      expect(line, contains('"order":"error"'));
    });

    test('入れ子の Map の中も均される', () {
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.info,
        op: 'x.y',
        detail: {
          'nested': {
            'at': DateTime(2026, 1, 2),
            'ids': const {9}
          },
        },
      ));

      expect(line, contains('"at":"2026-01-02T00:00:00.000"'));
      expect(line, contains('"ids":[9]'));
    });

    test('循環参照でも落ちずに 1 行を返す', () {
      // 素直に再帰すると StackOverflowError になり、OperationLogger が
      // その行を捨てる。深さの上限で畳んで行そのものは残す
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      final line = toJsonLine(
        LogEntry(ts: ts, lv: LogLevel.info, op: 'x.y', detail: cyclic),
      );

      expect(line, startsWith('{"ts":'));
      expect(line.contains('\n'), isFalse);
    });

    test('想定外の型でも落ちずに文字列になる', () {
      // ここで例外を投げると OperationLogger がその行を捨てる。
      // 落ちるより「何か入っていた」ことが残るほうが調査に使える
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.info,
        op: 'x.y',
        detail: const {'weird': Object()},
      ));

      expect(line, contains('"weird":"Instance of \'Object\'"'));
    });
  });

  group('JSON Lines として壊れない', () {
    test('改行を含む値でも 1 行に収まる', () {
      // SqliteException のメッセージは複数行になることがある。
      // 行の区切りが崩れるとファイル全体が読めなくなる
      final line = toJsonLine(LogEntry(
        ts: ts,
        lv: LogLevel.error,
        op: 'transaction.create',
        detail: const {'note': '1 行目\n2 行目'},
        error: '例外の 1 行目\n例外の 2 行目',
      ));

      expect(line.contains('\n'), isFalse);
      expect(line, contains(r'\n'));
    });
  });

  group('formatLogTimestamp', () {
    test('小数部は常にミリ秒 3 桁', () {
      // toIso8601String() はマイクロ秒の有無で 3 桁と 6 桁を行き来する。
      // 行ごとに幅が変わると目で追えず、期待値も書けない
      expect(
        formatLogTimestamp(DateTime(2026, 8, 17, 14, 3, 22, 481, 999)),
        '2026-08-17T14:03:22.481',
      );
      expect(
        formatLogTimestamp(DateTime(2026, 8, 17, 14, 3, 22)),
        '2026-08-17T14:03:22.000',
      );
    });

    test('1 桁の月日時分秒はゼロ詰めされる', () {
      expect(
        formatLogTimestamp(DateTime(2026, 1, 2, 3, 4, 5, 6)),
        '2026-01-02T03:04:05.006',
      );
    });
  });

  group('sanitizeError', () {
    /// sqlite3 が実際に出す形。`Causing statement:` の後ろにプレースホルダ入りの
    /// 文が来て、さらにその行の末尾へバインド値が並ぶ
    const sqliteMessage =
        'SqliteException(275): while executing statement, CHECK constraint '
        'failed: ("amount" > 0.0), constraint failed (code 275)\n'
        '  Causing statement: INSERT INTO "transactions" ("member_id", "memo") '
        'VALUES (?, ?), parameters: 1, ひみつの通院';

    test('バインド値は伏せる', () {
      final sanitized = sanitizeError(sqliteMessage);

      expect(sanitized, isNot(contains('ひみつの通院')));
      expect(sanitized, contains(', parameters: <省略>'));
    });

    test('失敗の理由と、どの文で落ちたかは残す', () {
      // 伏せすぎると「なぜ消せなかったか」がログから読めなくなる。
      // 文そのものはプレースホルダしか含まないので落とす理由がない
      final sanitized = sanitizeError(sqliteMessage);

      expect(sanitized, contains('CHECK constraint failed'));
      expect(sanitized, contains('INSERT INTO "transactions"'));
      expect(sanitized, contains('VALUES (?, ?)'));
    });

    test('parameters の後ろに続く行は消さない', () {
      // main.dart の app.uncaught は例外の後ろにスタックを繋いで渡す。
      // 例外以降を丸ごと捨てる実装にするとスタックまで消える
      final sanitized = sanitizeError(
        'SqliteException(19): ..., parameters: 1, ひみつの通院\n'
        '#0      main (package:ledger_app/main.dart:12:3)\n'
        '#1      _rootRun (dart:async/zone.dart:1391:13)',
      );

      expect(sanitized, isNot(contains('ひみつの通院')));
      expect(sanitized, contains('#0      main'));
      expect(sanitized, contains('#1      _rootRun'));
    });

    test('parameters を持たない例外はそのまま', () {
      expect(
        sanitizeError(StateError('Cannot operate on a closed database')),
        contains('Cannot operate on a closed database'),
      );
    });

    test('parameters が 2 回出てもどちらも伏せる', () {
      final sanitized = sanitizeError(
        'A, parameters: 1, ひみつ\nB, parameters: 2, ないしょ',
      );

      expect(sanitized, isNot(contains('ひみつ')));
      expect(sanitized, isNot(contains('ないしょ')));
      expect(sanitized, 'A, parameters: <省略>\nB, parameters: <省略>');
    });
  });
}
