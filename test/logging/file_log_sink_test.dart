import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/logging/file_log_sink.dart';
import 'package:path/path.dart' as p;

/// ログファイルへの追記と世代交代を確かめる。
///
/// [FileLogSink] は書き込み先のディレクトリを引数で受け取るので、ここでは
/// 一時ディレクトリを渡す。`path_provider` はプラグインで素の `flutter test`
/// では答えないため、パスの解決を sink の外（`main.dart`）に置いてある。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ledgercore_log_test');
  });
  tearDown(() async => dir.delete(recursive: true));

  File logFile() => File(p.join(dir.path, kLogFileName));
  File rotatedFile() => File(p.join(dir.path, kRotatedLogFileName));

  group('shouldRotate', () {
    test('上限を超える書き足しなら交代する', () {
      expect(
        shouldRotate(currentBytes: 900, incomingBytes: 200, maxBytes: 1000),
        isTrue,
      );
    });

    test('ちょうど上限までなら交代しない', () {
      expect(
        shouldRotate(currentBytes: 800, incomingBytes: 200, maxBytes: 1000),
        isFalse,
      );
    });

    test('空のファイルには 1 行が上限を超えていても交代しない', () {
      // ここを true にすると「毎回 rename して毎回空ファイルに書く」形になり、
      // 上限より長い行を書き続けると 1 本ずつ別ファイルへ散ってすべて失われる
      expect(
        shouldRotate(currentBytes: 0, incomingBytes: 5000, maxBytes: 1000),
        isFalse,
      );
    });
  });

  group('追記', () {
    test('書いた行が順に増える', () async {
      final sink = FileLogSink(dir);
      await sink.write('{"n":1}');
      await sink.write('{"n":2}');

      expect(
        await logFile().readAsString(),
        '{"n":1}\n{"n":2}\n',
      );
    });

    test('改行は sink が付ける（呼び出し側は付けない）', () async {
      await FileLogSink(dir).write('{"n":1}');
      expect(await logFile().readAsString(), endsWith('\n'));
    });

    test('既にあるファイルの続きに書く（消さない）', () async {
      await logFile().writeAsString('{"n":0}\n');
      await FileLogSink(dir).write('{"n":1}');

      expect(await logFile().readAsString(), '{"n":0}\n{"n":1}\n');
    });
  });

  group('世代交代', () {
    test('上限を超えると退避先へ移して本体を作り直す', () async {
      // 1 行 = 10 バイト（"0123456789" + 改行 ではなく、9 文字 + 改行）
      final sink = FileLogSink(dir, maxBytes: 25);
      await sink.write('012345678'); // 10 バイト
      await sink.write('012345678'); // 20 バイト
      await sink.write('012345678'); // 30 バイトになるので交代

      expect(await rotatedFile().readAsString(), '012345678\n012345678\n');
      expect(await logFile().readAsString(), '012345678\n');
    });

    test('残る世代は 1 つだけ（.2.log は作らない）', () async {
      final sink = FileLogSink(dir, maxBytes: 15);
      for (var i = 0; i < 6; i++) {
        await sink.write('012345678');
      }

      final names = dir.listSync().map((e) => p.basename(e.path));
      expect(names, unorderedEquals([kLogFileName, kRotatedLogFileName]));
    });

    test('交代を繰り返しても古い世代は最新の 1 つに置き換わる', () async {
      final sink = FileLogSink(dir, maxBytes: 15);
      await sink.write('AAAAAAAAA');
      await sink.write('BBBBBBBBB'); // A が退避
      await sink.write('CCCCCCCCC'); // B が退避（A は消える）

      expect(await rotatedFile().readAsString(), 'BBBBBBBBB\n');
      expect(await logFile().readAsString(), 'CCCCCCCCC\n');
    });

    test('上限は文字数ではなくバイトで測る', () async {
      // 日本語のカテゴリ名やメンバー名が入るので、文字数で数えると
      // 実際のファイルサイズが 3 倍近くまで膨らむ。
      // 「あ」は UTF-8 で 3 バイト。3 文字 + 改行 = 10 バイト
      final sink = FileLogSink(dir, maxBytes: 15);
      await sink.write('あああ');
      await sink.write('いいい');

      expect(await rotatedFile().readAsString(), 'あああ\n');
      expect(await logFile().readAsString(), 'いいい\n');
    });

    test('1 行が上限を超えていてもその行は失われない', () async {
      final sink = FileLogSink(dir, maxBytes: 5);
      await sink.write('とても長い 1 行');

      expect(await logFile().readAsString(), 'とても長い 1 行\n');
      expect(await rotatedFile().exists(), isFalse);
    });
  });
}
