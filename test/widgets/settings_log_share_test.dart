import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/logging/log_share.dart';
import 'package:ledger_app/logging/log_sink.dart';
import 'package:ledger_app/logging/operation_logger.dart';
import 'package:ledger_app/main.dart';

class _RecordingLogShare implements LogShare {
  final origins = <Rect>[];
  Future<bool> Function() result = () async => true;

  @override
  Future<bool> share({required Rect origin}) {
    origins.add(origin);
    return result();
  }
}

void main() {
  late AppDatabase db;
  late MemoryLogSink sink;
  late _RecordingLogShare share;
  const warning = 'ログにはカテゴリ名・メンバー名・金額が含まれます。共有先にご注意ください。';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sink = MemoryLogSink();
    share = _RecordingLogShare();
  });
  tearDown(() async => db.close());

  Future<void> pumpApp(
    WidgetTester tester, {
    bool noop = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      LedgerApp(
        db: db,
        clock: () => DateTime(2026, 7, 15),
        logger: OperationLogger(sink),
        logShare: noop ? null : share,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ログを共有'));
    await tester.pumpAndSettle();
  }

  Finder shareTile() =>
      find.ancestor(of: find.text('ログを共有'), matching: find.byType(ListTile));

  testWidgets('設定タブの導線が注意書きと矩形を持ち、押下がログに残る', (tester) async {
    await pumpApp(tester);
    expect(
      find.descendant(of: shareTile(), matching: find.text(warning)),
      findsOneWidget,
    );
    final expectedOrigin = tester.getRect(shareTile());
    await tester.tap(find.text('ログを共有'));
    await tester.pumpAndSettle();
    expect(share.origins, [expectedOrigin]);
    expect(expectedOrigin.isEmpty, isFalse);
    final entries = sink.lines
        .map((line) => jsonDecode(line) as Map)
        .where((entry) => entry['op'] == 'log.share');
    expect(entries, hasLength(1));
    expect(entries.single['lv'], 'info');
    expect(entries.single.containsKey('detail'), isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final noop in [false, true]) {
    testWidgets('空ログ・共有無効時は所定の SnackBar を出す: noop=$noop', (tester) async {
      share.result = () async => false;
      await pumpApp(tester, noop: noop);
      await tester.tap(find.text('ログを共有'));
      await tester.pumpAndSettle();
      expect(find.text('共有できるログがありません'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (!noop) expect(share.origins, hasLength(1));
    });
  }

  testWidgets('共有失敗を通知してログに残し、再試行できる', (tester) async {
    share.result = () async => throw StateError('共有シートを開けません');
    await pumpApp(tester);
    await tester.tap(find.text('ログを共有'));
    await tester.pumpAndSettle();
    expect(find.text('ログの共有に失敗しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final error = sink.lines
        .map((line) => jsonDecode(line) as Map)
        .singleWhere((entry) => entry['lv'] == 'error');
    expect(error['op'], 'log.share');
    expect(error['error'], contains('共有シートを開けません'));
    share.result = () async => true;
    await tester.tap(find.text('ログを共有'));
    await tester.pumpAndSettle();
    expect(share.origins, hasLength(2));
  });

  testWidgets('完了前の二重押下を防ぎ、完了後に有効へ戻す', (tester) async {
    final pending = Completer<bool>();
    share.result = () => pending.future;
    await pumpApp(tester);
    final tap = tester.widget<ListTile>(shareTile()).onTap!;
    tap();
    tap(); // 再描画前の競合も防ぐ。
    await tester.pump();
    expect(share.origins, hasLength(1));
    expect(tester.widget<ListTile>(shareTile()).enabled, isFalse);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(shareTile()).enabled, isTrue);
  });

  for (final afterFrame in [false, true]) {
    for (final fails in [false, true]) {
      testWidgets('共有中にタブを離れても通知を出さない: 描画後=$afterFrame, error=$fails', (
        tester,
      ) async {
        final pending = Completer<bool>();
        share.result = () => pending.future;
        await pumpApp(tester);
        await tester.tap(find.text('ログを共有'));
        await tester.pump();
        expect(share.origins, hasLength(1));
        await tester.tap(find.text('ホーム'));
        if (afterFrame) await tester.pumpAndSettle();
        if (fails) {
          pending.completeError(StateError('遅れて失敗'));
        } else {
          pending.complete(false);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsNothing);
      });
    }
  }

  testWidgets('文字倍率2倍でも注意書きを省略せず読める', (tester) async {
    await pumpApp(tester, scale: 2);
    await tester.ensureVisible(find.text(warning));
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(find.text(warning));
    expect(paragraph.maxLines, isNull);
    expect(paragraph.size.height, greaterThan(100));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ログを共有'));
    await tester.pumpAndSettle();
    expect(share.origins, hasLength(1));
  });
}
