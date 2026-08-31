import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/logging/log_sink.dart';
import 'package:ledger_app/logging/operation_logger.dart';

/// [OperationLogger] の約束を確かめる。
///
/// - 呼び出し側に await させない（[OperationLogger.info] は `void`）
/// - それでも**呼んだ順に**書き出される
/// - 時刻は呼び出し時点で確定する
/// - 書き込みが失敗してもアプリの操作を壊さない
void main() {
  Map<String, Object?> decode(String line) =>
      jsonDecode(line) as Map<String, Object?>;

  group('行の中身', () {
    test('info は lv:info で、注入した時計の時刻を使う', () async {
      final sink = MemoryLogSink();
      final logger = OperationLogger(
        sink,
        clock: () => DateTime(2026, 8, 17, 14, 3, 22, 481),
      );

      logger.info('transaction.create', detail: {'amount': 1200.0});
      await logger.flush();

      expect(sink.lines, hasLength(1));
      final entry = decode(sink.lines.single);
      expect(entry['ts'], '2026-08-17T14:03:22.481');
      expect(entry['lv'], 'info');
      expect(entry['op'], 'transaction.create');
      expect(entry['detail'], {'amount': 1200.0});
    });

    test('error は lv:error と例外の文字列を載せる', () async {
      final sink = MemoryLogSink();
      final logger = OperationLogger(sink, clock: () => DateTime(2026, 8, 17));

      logger.error(
        'transaction.delete',
        StateError('制約違反'),
        detail: {'id': 42},
      );
      await logger.flush();

      final entry = decode(sink.lines.single);
      expect(entry['lv'], 'error');
      expect(entry['op'], 'transaction.delete');
      expect(entry['error'], contains('制約違反'));
    });

    test('時計は書き換えられる変数でも呼ぶたびに読み直す', () async {
      // 「今」を 1 度だけ読んでキャッシュしていないことを見る。
      // 併せて **ts が呼び出し時点で確定する**ことの回帰でもある
      // （キュー消化時に読むと、詰まったぶんだけ後ろへずれる）
      var now = DateTime(2026, 8, 17, 10);
      final sink = MemoryLogSink();
      final logger = OperationLogger(sink, clock: () => now);

      logger.info('a');
      now = DateTime(2026, 8, 17, 11);
      logger.info('b');
      await logger.flush();

      expect(decode(sink.lines[0])['ts'], startsWith('2026-08-17T10:'));
      expect(decode(sink.lines[1])['ts'], startsWith('2026-08-17T11:'));
    });

    test('noop は info も error も投げずに飲み込む', () async {
      // **expect が 1 つも無いと「投げないこと」すら検証していない。**
      // OperationLogger は sink の例外を握りつぶす設計なので、
      // NoopLogSink が実際に投げるようになっても素通りしてしまう
      final logger = OperationLogger.noop();
      logger.info('transaction.create');
      logger.error('transaction.create', StateError('boom'));

      await expectLater(logger.flush(), completes);
      await expectLater(const NoopLogSink().write('x'), completes);
    });
  });

  group('呼び出し側を待たせない', () {
    test('書き出しが遅くても info はその完了を待たずに戻る', () async {
      // 遅い sink を使うのが肝。MemoryLogSink は await を挟まないので
      // 1 件目がその場で書き終わってしまい、待たされているのか
      // 速いだけなのかを区別できない
      final sink = _DelayedLogSink([const Duration(milliseconds: 50)]);
      final logger = OperationLogger(sink);

      logger.info('transaction.create');
      // sink がまだ書き終えていないうちに制御が戻っている。
      // ここで 1 件になる実装は、呼び出し側をファイル I/O で待たせている
      expect(sink.lines, isEmpty);

      await logger.flush();
      expect(sink.lines, hasLength(1));
    });
  });

  group('順序', () {
    test('読み出しは先行する書き込みを待ち、完了まで後続の書き込みを止める', () async {
      final sink = _DelayedLogSink([const Duration(milliseconds: 50)]);
      final logger = OperationLogger(sink);
      final started = Completer<void>();
      final release = Completer<void>();
      logger.info('before');
      final reading = logger.withPausedWrites(() async {
        started.complete();
        await release.future;
        return sink.lines.map((line) => decode(line)['op']).toList();
      });
      await started.future;
      expect(sink.lines.map((line) => decode(line)['op']), ['before']);
      logger.info('after');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sink.lines.map((line) => decode(line)['op']), ['before']);
      release.complete();
      expect(await reading, ['before']);
      await logger.flush();
      expect(sink.lines.map((line) => decode(line)['op']), ['before', 'after']);
    });

    test('書き出しが遅い行があっても呼んだ順に並ぶ', () async {
      // 1 件目だけ書き込みが遅い sink を使う。各呼び出しが独立に write を
      // 始める実装だと、完了の速い 2 件目が先にファイルへ着いて
      // 「削除のあとに追加」のような読めないログになる
      final sink = _DelayedLogSink([const Duration(milliseconds: 50)]);
      final logger = OperationLogger(sink);

      logger.info('first');
      logger.info('second');
      await logger.flush();

      expect(sink.lines.map((l) => decode(l)['op']).toList(), [
        'first',
        'second',
      ]);
    });

    test('連続して積んだ 10 件が順番どおりに並ぶ', () async {
      final sink = MemoryLogSink();
      final logger = OperationLogger(sink);

      for (var i = 0; i < 10; i++) {
        logger.info('op.$i');
      }
      await logger.flush();

      expect(
        sink.lines.map((l) => decode(l)['op']).toList(),
        List.generate(10, (i) => 'op.$i'),
      );
    });
  });

  group('失敗しても操作を壊さない', () {
    test('sink が例外を投げても info は例外を投げない', () async {
      final sink = MemoryLogSink()..failWith = StateError('書き込み先が一杯');
      final logger = OperationLogger(sink);

      logger.info('transaction.create');
      // flush まで含めて例外が漏れないこと。ここで漏れると、書き込み先が
      // 埋まった端末で家計簿そのものが操作不能になる
      await logger.flush();
      expect(sink.lines, isEmpty);
    });

    test('1 件失敗しても後続は書かれる', () async {
      final sink = MemoryLogSink()..failWith = StateError('一時的な失敗');
      final logger = OperationLogger(sink);

      logger.info('first');
      await logger.flush();

      sink.failWith = null;
      logger.info('second');
      await logger.flush();

      expect(sink.lines.map((l) => decode(l)['op']).toList(), ['second']);
    });

    test('循環参照の detail でも行は失われず、後続も書かれる', () async {
      final sink = MemoryLogSink();
      final logger = OperationLogger(sink);

      // 自分自身を含む Map。素直に再帰すると StackOverflowError になり、
      // その行が丸ごと消える。深さの上限で畳んで行は残す
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      logger.info('cyclic', detail: cyclic);
      logger.info('fine');
      await logger.flush();

      expect(sink.lines.map((l) => decode(l)['op']).toList(), [
        'cyclic',
        'fine',
      ]);
    });
  });
}

/// 指定した時間だけ待ってから記録する [LogSink]。書き出しの順序を確かめるために使う
class _DelayedLogSink implements LogSink {
  final List<String> lines = [];
  final List<Duration> delays;
  int _index = 0;

  _DelayedLogSink(this.delays);

  @override
  Future<void> write(String line) async {
    final delay = _index < delays.length ? delays[_index] : Duration.zero;
    _index++;
    await Future.delayed(delay);
    lines.add(line);
  }
}
