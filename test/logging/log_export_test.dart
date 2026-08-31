import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/logging/file_log_sink.dart';
import 'package:ledger_app/logging/log_export.dart';
import 'package:path/path.dart' as p;

void main() {
  test('退避→現行の順に日本語と改行をそのまま連結する', () {
    expect(combineLogs(rotated: '古いログ\n', current: '現在のログ\n'), '古いログ\n現在のログ\n');
  });

  test('退避の末尾改行がなくても行をつなげない', () {
    expect(combineLogs(rotated: '古いログ', current: '新しいログ'), '古いログ\n新しいログ');
  });

  for (final sample in [('', ''), ('退避だけ', ''), ('', '現行だけ')]) {
    test('片方だけ・両方空でも余分な行を作らない: $sample', () {
      expect(
        combineLogs(rotated: sample.$1, current: sample.$2),
        '${sample.$1}${sample.$2}',
      );
    });
  }

  test('日時を固定桁にし、拡張子が txt のファイル名を組み立てる', () {
    expect(
      logExportFileName(DateTime(2026, 1, 2, 3, 4, 5)),
      'ledgercore-20260102-030405.txt',
    );
    expect(
      logExportFileName(DateTime(2026, 12, 31, 23, 59, 59)),
      'ledgercore-20261231-235959.txt',
    );
  });

  group('ファイルから読み出す', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('log_export_test-');
    });
    tearDown(() async => directory.delete(recursive: true));

    for (final sample in [
      ('退避\n', '現行\n', '退避\n現行\n'),
      ('退避\n', null, '退避\n'),
      (null, '現行\n', '現行\n'),
      (null, null, ''),
      ('', '', ''),
    ]) {
      test('存在するログだけを読み、DB と無関係なファイルには触らない: $sample', () async {
        final old = File(p.join(directory.path, kRotatedLogFileName));
        final current = File(p.join(directory.path, kLogFileName));
        final db = File(p.join(directory.path, 'ledgercore.sqlite'));
        await db.writeAsString('共有してはいけないDB');
        if (sample.$1 != null) await old.writeAsString(sample.$1!);
        if (sample.$2 != null) await current.writeAsString(sample.$2!);

        expect(await readLogsForExport(directory), sample.$3);
        expect(await db.readAsString(), '共有してはいけないDB');
        if (sample.$1 != null) expect(await old.readAsString(), sample.$1);
        if (sample.$2 != null) expect(await current.readAsString(), sample.$2);
      });
    }
  });
}
