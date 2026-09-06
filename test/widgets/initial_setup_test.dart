import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/screens/initial_setup_screen.dart';
import 'package:ledger_app/screens/main_screen.dart';

import '../seed.dart';

/// 起動判定と初期設定を、`LedgerApp` ごと pump して確かめる。
///
/// 初期設定を迂回するテスト専用フラグは作らない（本番に無い経路を作ると、
/// 「アプリを起動すると何が出るか」を守るテストが 1 本も無くなる）。
/// 読み取り・保存の失敗は、DB を差し替えて起こす。
void main() {
  /// 指定した回数だけ失敗する DB。
  ///
  /// 閉じた DB で起こす手もあるが、それだと**再試行しても永久に失敗する**ので
  /// 「再試行が本当に読み直したか」を確かめられない。
  late _FlakyDatabase db;

  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = _FlakyDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpApp(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();
  }

  /// アプリを終了して起動し直す。
  ///
  /// **同じ `LedgerApp` をもう一度 pump するだけでは再起動にならない。**
  /// ウィジェットの型も位置も同じなので `State` が再利用され、入力欄の
  /// `TextEditingController` も Provider も前のまま残る（実測: 前回入力した
  /// 名前が新しい起動の画面に出たままになる）。間に別のツリーを挟んで捨てる。
  Future<void> restartApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpApp(tester);
  }

  Future<void> enterNames(
    WidgetTester tester,
    String first,
    String second,
  ) async {
    await tester.enterText(find.byType(TextFormField).first, first);
    await tester.enterText(find.byType(TextFormField).last, second);
  }

  Future<void> tapStart(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'はじめる'));
    await tester.pumpAndSettle();
  }

  group('起動判定', () {
    testWidgets('新規 DB では初期設定を表示し、通常画面は作らない', (tester) async {
      await pumpApp(tester);

      expect(find.byType(InitialSetupScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('DB を読み終えるまでは起動判定中の表示を出す', (tester) async {
      tester.view.physicalSize = const Size(360, 690);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // インメモリ DB は速すぎて、素直に pump すると読み取りが済んでしまう。
      // 完了を握って、読んでいる最中のフレームを作る
      final reading = Completer<void>();
      db.holdReads = reading;

      await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byType(InitialSetupScreen), findsNothing);

      reading.complete();
      await tester.pumpAndSettle();
      expect(find.byType(InitialSetupScreen), findsOneWidget);
    });

    for (final names in [
      ['自分'],
      ['自分', 'パートナー'],
      // 旧版由来で 3 人以上いる端末も初期設定へ戻さない
      ['自分', 'パートナー', '家族'],
    ]) {
      testWidgets('メンバー${names.length}件なら通常画面を表示する', (tester) async {
        await seedMembers(db, names);

        await pumpApp(tester);

        expect(find.byType(MainScreen), findsOneWidget);
        expect(find.byType(InitialSetupScreen), findsNothing);
      });
    }

    testWidgets('メンバー0件でも取引が残っていればデータ不整合として止まる', (tester) async {
      await seedMembers(db);
      await db.insertTransaction(
        TransactionInput(
          memberId: (await db.getMembers()).first.id,
          categoryId: (await db.getCategories()).first.id,
          amount: 1000,
          spentAt: DateTime(2026, 7, 1),
        ),
      );
      // 取引だけが残る壊れた状態を作る（FK があるので外して消す）
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement('DELETE FROM members');
      await db.customStatement('PRAGMA foreign_keys = ON');

      await pumpApp(tester);

      expect(find.textContaining('取引が残っています'), findsOneWidget);
      // 新しいメンバーを登録させない。既存の取引と無関係な支払者が増える
      expect(find.byType(InitialSetupScreen), findsNothing);
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('読み取りに失敗したら0件扱いにせず、エラーと再試行を出す', (tester) async {
      db.failingReads = 1;

      await pumpApp(tester);

      expect(find.textContaining('読み込みに失敗'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '再試行'), findsOneWidget);
      expect(find.byType(InitialSetupScreen), findsNothing);
      expect(find.byType(MainScreen), findsNothing);
    });

    testWidgets('再試行で読み直し、成功すれば初期設定へ進む', (tester) async {
      db.failingReads = 1;
      await pumpApp(tester);

      await tester.tap(find.widgetWithText(FilledButton, '再試行'));
      await tester.pumpAndSettle();

      expect(find.byType(InitialSetupScreen), findsOneWidget);
      expect(find.textContaining('読み込みに失敗'), findsNothing);
    });

    testWidgets('既存メンバーがいる端末で読み取りに失敗しても、通常画面は出さない', (tester) async {
      await seedMembers(db, const ['自分', 'パートナー']);
      db.failingReads = 1;

      await pumpApp(tester);

      expect(find.textContaining('読み込みに失敗'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '再試行'));
      await tester.pumpAndSettle();
      expect(find.byType(MainScreen), findsOneWidget);
    });
  });

  group('入力の検証', () {
    testWidgets('空欄では登録できない', (tester) async {
      await pumpApp(tester);

      await tapStart(tester);

      expect(find.text('名前を入力してください'), findsNWidgets(2));
      expect(await db.getMembers(), isEmpty);
      expect(find.byType(InitialSetupScreen), findsOneWidget);
    });

    testWidgets('空白だけの名前も登録できない', (tester) async {
      await pumpApp(tester);

      await enterNames(tester, '  ', 'はなこ');
      await tapStart(tester);

      expect(find.text('名前を入力してください'), findsOneWidget);
      expect(await db.getMembers(), isEmpty);
    });

    testWidgets('50文字は登録でき、51文字は登録できない', (tester) async {
      await pumpApp(tester);

      await enterNames(tester, 'あ' * 51, 'い' * 50);
      await tapStart(tester);
      expect(find.text('名前は50文字までです'), findsOneWidget);
      expect(await db.getMembers(), isEmpty);

      await enterNames(tester, 'あ' * 50, 'い' * 50);
      await tapStart(tester);
      expect((await db.getMembers()).map((m) => m.name), ['あ' * 50, 'い' * 50]);
    });

    testWidgets('前後の空白は落として登録する', (tester) async {
      await pumpApp(tester);

      await enterNames(tester, '  たろう  ', ' はなこ ');
      await tapStart(tester);

      expect((await db.getMembers()).map((m) => m.name), ['たろう', 'はなこ']);
    });

    testWidgets('2人が同名でも登録できる', (tester) async {
      await pumpApp(tester);

      await enterNames(tester, 'ゆう', 'ゆう');
      await tapStart(tester);

      expect((await db.getMembers()).map((m) => m.name), ['ゆう', 'ゆう']);
      expect(find.byType(MainScreen), findsOneWidget);
    });
  });

  group('保存と画面切り替え', () {
    testWidgets('保存に成功するとルートが通常画面へ切り替わる', (tester) async {
      await pumpApp(tester);

      await enterNames(tester, 'たろう', 'はなこ');
      await tapStart(tester);

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(InitialSetupScreen), findsNothing);
      // Navigator に積まないので、初期設定へ戻る導線は残らない
      expect(find.byType(BackButton), findsNothing);
      expect(await db.countMembers(), 2);
    });

    testWidgets('スキップも戻る導線も無い', (tester) async {
      await pumpApp(tester);

      expect(find.text('スキップ'), findsNothing);
      expect(find.text('あとで'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('保存に失敗したら入力を保ったまま残り、再試行できる', (tester) async {
      db.failingWrites = 1;
      await pumpApp(tester);

      await enterNames(tester, 'たろう', 'はなこ');
      await tester.tap(find.widgetWithText(FilledButton, 'はじめる'));
      await tester.pump();

      expect(find.text('保存に失敗しました。もう一度お試しください'), findsOneWidget);
      expect(find.byType(InitialSetupScreen), findsOneWidget);
      // 入力内容は消えない
      expect(find.text('たろう'), findsOneWidget);
      expect(find.text('はなこ'), findsOneWidget);
      // 1 人も登録されていない（保存前に終了した端末は次回も初期設定）
      expect(await db.getMembers(), isEmpty);

      // 通知が保存ボタンを覆って再試行できなくならないこと
      final snackBar = tester.getRect(find.byType(SnackBar));
      final button = tester.getRect(find.widgetWithText(FilledButton, 'はじめる'));
      expect(snackBar.overlaps(button), isFalse);

      await tapStart(tester);
      expect(find.byType(MainScreen), findsOneWidget);
      expect((await db.getMembers()).map((m) => m.name), ['たろう', 'はなこ']);
    });

    testWidgets('保存前に終了した端末は、次の起動でも初期設定を表示する', (tester) async {
      db.failingWrites = 1;
      await pumpApp(tester);
      await enterNames(tester, 'たろう', 'はなこ');
      await tapStart(tester);

      await restartApp(tester);

      expect(find.byType(InitialSetupScreen), findsOneWidget);
      expect(find.text('たろう'), findsNothing);
    });

    testWidgets('同じ DB の2回目以降の起動では初期設定を表示しない', (tester) async {
      await pumpApp(tester);
      await enterNames(tester, 'たろう', 'はなこ');
      await tapStart(tester);

      await restartApp(tester);

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(InitialSetupScreen), findsNothing);
      expect(await db.countMembers(), 2);
    });

    testWidgets('文字倍率2.0でも崩れず登録できる', (tester) async {
      await pumpApp(tester, scale: 2.0);

      expect(tester.takeException(), isNull);
      await enterNames(tester, 'たろう', 'はなこ');
      await tapStart(tester);

      expect(tester.takeException(), isNull);
      expect(await db.countMembers(), 2);
    });
  });
}

/// 指定回数だけ読み取り・書き込みを失敗させる DB。
class _FlakyDatabase extends AppDatabase {
  _FlakyDatabase(super.executor) : super.forTesting();

  int failingReads = 0;
  int failingWrites = 0;

  /// 完了させるまで読み取りを待たせる。起動判定中の表示を見るために使う
  Completer<void>? holdReads;

  @override
  Future<int> countMembers() async {
    final hold = holdReads;
    if (hold != null) {
      holdReads = null;
      await hold.future;
    }
    if (failingReads > 0) {
      failingReads--;
      throw StateError('読み取りに失敗しました');
    }
    return super.countMembers();
  }

  @override
  Future<void> insertInitialMembers(String first, String second) {
    if (failingWrites > 0) {
      failingWrites--;
      return Future.error(StateError('書き込みに失敗しました'));
    }
    return super.insertInitialMembers(first, second);
  }
}
