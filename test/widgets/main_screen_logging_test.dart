import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/logging/log_sink.dart';
import 'package:ledger_app/logging/operation_logger.dart';
import 'package:ledger_app/main.dart';

/// タブの切り替えと画面遷移がログに残るかを、**実際に押して**確かめる。
///
/// この 2 つは Provider を通らず画面から直接ログを出す唯一の経路なので、
/// Provider のテストでは代替できない（`test/provider_logging_test.dart` は
/// `MainScreen` を組み立てない）。配線が外れても Provider 側は緑のままになる。
void main() {
  late AppDatabase db;
  late MemoryLogSink sink;
  late OperationLogger logger;

  final fixedNow = DateTime(2026, 7, 15);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sink = MemoryLogSink();
    logger = OperationLogger(sink, clock: () => fixedNow);
  });
  tearDown(() async => db.close());

  List<Map<String, Object?>> entries() =>
      sink.lines.map((l) => jsonDecode(l) as Map<String, Object?>).toList();

  List<Map<String, Object?>> entriesOf(String op) =>
      entries().where((e) => e['op'] == op).toList();

  /// 積まれたログが書き出されるまでフレームを進める。
  ///
  /// **`testWidgets` の中で `logger.flush()` を待ってはいけない。** ロガーの
  /// キューは `info()` を呼んだ擬似時間のゾーンに積まれる。これを
  /// `tester.runAsync`（擬似時間を止めて実時間で走らせる）の中で待つと、
  /// キューを流す側と待つ側が互いを待ってデッドロックし、`pumpAndSettle` の
  /// 既定タイムアウト 10 分ぶん黙ってハングする（失敗としては出ない）。
  ///
  /// マイクロタスクはフレームを進めれば流れるので、`pump` を 1 つ挟めば足りる。
  Future<void> flushLog(WidgetTester tester) => tester.pump();

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LedgerApp(db: db, clock: () => fixedNow, logger: logger),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('タブを押すと tab.change が残る', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('取引'));
    await tester.pumpAndSettle();
    await flushLog(tester);

    final changes = entriesOf('tab.change');
    expect(changes, hasLength(1));
    // 画面の文言ではなく英字のタブ名で残す（文言を変えても集計が壊れないように）
    expect(changes.single['detail'], {'from': 'summary', 'to': 'transactions'});
  });

  testWidgets('タブ構成がホーム・取引・割り勘・設定になる', (tester) async {
    await pumpApp(tester);

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    final destinations =
        navigationBar.destinations.cast<NavigationDestination>().toList();

    expect(destinations.map((destination) => (destination.icon as Icon).icon), [
      Icons.bar_chart_outlined,
      Icons.receipt_long_outlined,
      Icons.balance_outlined,
      Icons.settings_outlined,
    ]);
    expect(
      destinations.map(
        (destination) => (destination.selectedIcon! as Icon).icon,
      ),
      [Icons.bar_chart, Icons.receipt_long, Icons.balance, Icons.settings],
    );
    expect(find.byIcon(Icons.people_outline), findsNothing);
  });

  testWidgets('タブを渡り歩いた順がそのまま残る', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('割り勘'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await flushLog(tester);

    expect(entriesOf('tab.change').map((e) => e['detail']).toList(), [
      {'from': 'summary', 'to': 'split'},
      {'from': 'split', 'to': 'settings'},
    ]);
  });

  testWidgets('選択中のタブを押し直しても残さない', (tester) async {
    await pumpApp(tester);

    // NavigationBar は同じ行き先でもコールバックを呼ぶ。素直に書くと
    // from と to が同じ行がログに溜まる
    await tester.tap(find.text('ホーム'));
    await tester.pumpAndSettle();
    await flushLog(tester);

    expect(entriesOf('tab.change'), isEmpty);
  });

  testWidgets('設定から管理画面を開くと screen.open が残る', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('リマインド'), findsNothing);
    expect(find.text('月の開始日'), findsNothing);
    expect(find.text('データ書き出し'), findsNothing);

    await tester.tap(find.text('カテゴリ管理'));
    await tester.pumpAndSettle();
    await flushLog(tester);
    expect(find.widgetWithText(AppBar, 'カテゴリ管理'), findsOneWidget);
    expect(entriesOf('screen.open').last['detail'], {'name': 'categories'});

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('メンバー管理'));
    await tester.pumpAndSettle();
    await flushLog(tester);

    expect(find.widgetWithText(AppBar, 'メンバー管理'), findsOneWidget);
    expect(entriesOf('screen.open').last['detail'], {'name': 'members'});
  });

  testWidgets('月送りの矢印を押すと month.change が残る', (tester) async {
    // 画面 → Provider の配線まで通っていることを実際の操作で見る
    await pumpApp(tester);

    await tester.tap(find.text('取引'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await flushLog(tester);

    expect(entriesOf('month.change').last['detail'], {
      'from': '2026-07',
      'to': '2026-06',
      'via': 'arrow',
    });
  });

  testWidgets('ロガーを渡さなくても起動して操作できる', (tester) async {
    // production の初期化に失敗した端末でも家計簿は使える
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取引'));
    await tester.pumpAndSettle();

    // ロガーを渡さなくても LedgerApp がツリーへ 1 つ置くこと。
    // 置き忘れると main_screen の context.read<OperationLogger>() が
    // ProviderNotFoundException を投げ、タブが切り替わらなくなる
    expect(tester.takeException(), isNull);
    expect(find.text('取引一覧'), findsOneWidget);
  });
}
