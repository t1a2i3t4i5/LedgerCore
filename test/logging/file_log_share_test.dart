import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/logging/file_log_share.dart';
import 'package:ledger_app/logging/file_log_sink.dart';
import 'package:ledger_app/logging/log_share.dart';
import 'package:ledger_app/logging/operation_logger.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory documents;
  late Directory temporary;
  late OperationLogger logger;
  const origin = Rect.fromLTWH(16, 320, 328, 100);
  const channel = MethodChannel('dev.fluttercommunity.plus/share');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('log_share_test-');
    documents = await Directory(p.join(root.path, 'documents')).create();
    temporary = await Directory(p.join(root.path, 'temporary')).create();
    logger = OperationLogger(FileLogSink(documents));
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await logger.flush();
    await root.delete(recursive: true);
  });

  FileLogShare createShare({
    Future<void> Function(File, Rect)? shareFile,
    Future<Directory> Function()? temporaryDirectory,
  }) => FileLogShare(
    directory: documents,
    logger: logger,
    temporaryDirectory: temporaryDirectory ?? () async => temporary,
    shareFile: shareFile,
    clock: () => DateTime(2026, 8, 31, 9, 5, 7),
  );

  test('共有を無効にしても false で戻る', () async {
    expect(await const NoopLogShare().share(origin: origin), isFalse);
  });

  for (final contents in [null, '', '\n \n']) {
    test('ログがない場合は共有も一時ファイル作成もせず false: $contents', () async {
      if (contents != null) {
        await File(
          p.join(documents.path, kLogFileName),
        ).writeAsString(contents);
      }
      var calls = 0;
      final share = createShare(shareFile: (_, __) async => calls++);
      expect(await share.share(origin: origin), isFalse);
      expect(calls, 0);
      expect(await temporary.list().toList(), isEmpty);
    });
  }

  test('押下の記録だけで空ログを共有してしまわない', () async {
    var calls = 0;
    final pending = createShare(
      shareFile: (_, __) async => calls++,
    ).share(origin: origin);
    logger.info('log.share');
    expect(await pending, isFalse);
    await logger.flush();
    expect(calls, 0);
    expect(
      await File(p.join(documents.path, kLogFileName)).readAsString(),
      contains('log.share'),
    );
  });

  test('1本の txt を正しい内容・MIME・矩形でプラグインへ渡し、キャンセル後に消す', () async {
    await File(
      p.join(documents.path, kRotatedLogFileName),
    ).writeAsString('退避\n');
    await File(p.join(documents.path, kLogFileName)).writeAsString('現行\n');
    final db = File(p.join(documents.path, 'ledgercore.sqlite'));
    await db.writeAsString('DBは非公開');
    var calls = 0;
    String? sharedPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          expect(call.method, 'share');
          final args = call.arguments as Map;
          expect(args['paths'], hasLength(1));
          sharedPath = (args['paths'] as List).single as String;
          expect(p.isWithin(temporary.path, sharedPath!), isTrue);
          expect(p.basename(sharedPath!), 'ledgercore-20260831-090507.txt');
          expect(await File(sharedPath!).readAsString(), '退避\n現行\n');
          expect(args['mimeTypes'], ['text/plain']);
          expect(args['originX'], 16);
          expect(args['originY'], 320);
          expect(args['originWidth'], 328);
          expect(args['originHeight'], 100);
          return ''; // OS のキャンセル結果。
        });

    expect(await createShare().share(origin: origin), isTrue);
    expect(calls, 1);
    expect(await File(sharedPath!).exists(), isFalse);
    expect(await temporary.list().toList(), isEmpty);
    expect(await db.readAsString(), 'DBは非公開');
    expect(
      await File(p.join(documents.path, kLogFileName)).readAsString(),
      '現行\n',
    );
  });

  test('書き込み待ちと世代交代を済ませてから読み、後続の書き込みを待たせる', () async {
    logger = OperationLogger(FileLogSink(documents, maxBytes: 1));
    logger.info('first');
    logger.info('second'); // first が退避される。
    String? shared;
    final pending = createShare(
      shareFile: (file, _) async {
        shared = await file.readAsString();
      },
    ).share(origin: origin);
    logger.info('third'); // 読み出しの後で first を消す世代交代。
    expect(await pending, isTrue);
    await logger.flush();
    expect(shared, contains('first'));
    expect(shared, contains('second'));
    expect(shared!.indexOf('first'), lessThan(shared!.indexOf('second')));
    expect(shared, isNot(contains('third')));
    expect(
      await File(p.join(documents.path, kLogFileName)).readAsString(),
      contains('third'),
    );
  });

  test('共有シートの待機中もログを書け、重複して共有せず、完了後は再度共有できる', () async {
    logger.info('before');
    final opened = Completer<void>();
    final finish = Completer<void>();
    var calls = 0;
    final share = createShare(
      shareFile: (_, __) async {
        calls++;
        if (calls == 1) {
          opened.complete();
          await finish.future;
        }
      },
    );
    final pending = share.share(origin: origin);
    await opened.future;
    logger.info('during');
    await logger.flush();
    expect(
      await File(p.join(documents.path, kLogFileName)).readAsString(),
      contains('during'),
    );
    expect(await share.share(origin: origin), isTrue);
    expect(calls, 1);
    finish.complete();
    expect(await pending, isTrue);
    expect(await share.share(origin: origin), isTrue);
    expect(calls, 2);
  });

  test('共有の例外を通知し、コピーを削除してから再試行できる', () async {
    logger.info('before');
    var fail = true;
    final share = createShare(
      shareFile: (_, __) async {
        if (fail) throw PlatformException(code: 'share_failed');
      },
    );
    await expectLater(
      share.share(origin: origin),
      throwsA(isA<PlatformException>()),
    );
    expect(await temporary.list().toList(), isEmpty);
    fail = false;
    expect(await share.share(origin: origin), isTrue);
  });

  test('読み出し失敗後もロガーが動き、修復後に共有できる', () async {
    final file = File(p.join(documents.path, kLogFileName));
    await file.writeAsBytes([0xff]); // 不正な UTF-8。
    final share = createShare(shareFile: (_, __) async {});
    await expectLater(
      share.share(origin: origin),
      throwsA(isA<FileSystemException>()),
    );
    await file.writeAsString('');
    logger.info('recovered');
    await logger.flush();
    expect(await file.readAsString(), contains('recovered'));
    expect(await share.share(origin: origin), isTrue);
  });

  test('一時領域が取得できない失敗でも再試行できる', () async {
    logger.info('before');
    var fail = true;
    final share = createShare(
      temporaryDirectory: () async {
        if (fail) throw const FileSystemException('一時領域を取得できない');
        return temporary;
      },
      shareFile: (_, __) async {},
    );
    await expectLater(
      share.share(origin: origin),
      throwsA(isA<FileSystemException>()),
    );
    fail = false;
    expect(await share.share(origin: origin), isTrue);
  });
}
