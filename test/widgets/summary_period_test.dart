import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/summary_screen.dart';
import 'package:ledger_app/widgets/ledger_card.dart';
import 'package:ledger_app/widgets/month_selector.dart';
import 'package:ledger_app/widgets/page_header.dart';
import 'package:ledger_app/widgets/period_format.dart';
import 'package:provider/provider.dart';

/// 集計画面の月／年／全期間の切り替えを、実際に画面を押して見る。
///
/// Provider の状態遷移は summary_provider_test.dart が見ている。ここで見るのは
/// **配線** — セグメントを押したらモードが変わるか、年モードの矢印が年送りに
/// なっているか、モードごとに正しいものが描かれるか。CLAUDE.md が言う
/// 「画面の配線は Provider のテストでは代替できない」がこれにあたる。
void main() {
  late AppDatabase db;

  // 表示期間を実時刻から切り離す。「今年」にテストデータを置かない
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seed(
    DateTime spentAt,
    double amount, {
    int categoryIndex = 0,
  }) async {
    final categories = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: categories[categoryIndex].id,
        amount: amount,
        spentAt: spentAt,
      ),
    );
  }

  /// 年ごと・月ごとに金額を変えて「どの期間を読んだか」を金額で判別できるようにする。
  /// 2025 年 = 250 / 2026 年 = 300（3 月）+ 700（7 月）= 1000
  Future<void> seedTwoYears() async {
    await seed(DateTime(2025, 3, 5), 250);
    await seed(DateTime(2026, 3, 5), 300, categoryIndex: 1);
    await seed(DateTime(2026, 7, 5), 700);
  }

  Future<void> pumpSummary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SummaryProvider(db, clock: () => fixedNow),
        child: const MaterialApp(home: Scaffold(body: SummaryScreen())),
      ),
    );
    // initState の postFrameCallback で fetch が走るので落ち着かせる
    await tester.pumpAndSettle();
  }

  /// 期間セグメントを押す。'月' / '年' / '全期間' は完全一致で拾える
  /// （MonthSelector が出す '2026年7月' とは別物）
  Future<void> tapPeriod(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  bool todayIsEnabled(WidgetTester tester) =>
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.text('今年'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;

  group('初期表示', () {
    testWidgets('月モードで始まり、グラフは出ない', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      expect(find.text('2026年7月'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
      // 月モードは 7 月ぶん
      expect(find.text('¥700'), findsWidgets);
      expect(find.text('メンバー別'), findsOneWidget);
    });
  });

  group('年モード', () {
    testWidgets('推移グラフが出て、ヘッダが年だけになる', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      await tapPeriod(tester, '年');

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text(formatPeriod(2026, null)), findsOneWidget);
      expect(find.text('${formatPeriod(2026, null)}の支出'), findsOneWidget);
      expect(find.text('2026年7月'), findsNothing);
      // 年合計。月モードの ¥700 から入れ替わっている
      expect(find.text('¥1,000'), findsWidgets);
      expect(find.text('月別の推移'), findsOneWidget);
    });

    // YearlySummary に byMember が無いため（design-notes.md 参照）
    testWidgets('メンバー別は出さない', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      await tapPeriod(tester, '年');

      expect(find.text('メンバー別'), findsNothing);
      expect(find.text('カテゴリ別'), findsOneWidget);
    });

    // 月合計を分母にすると 100.0% になるので、取り違えるとここで落ちる
    testWidgets('カテゴリ別の構成比が年合計を分母にする', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      await tapPeriod(tester, '年');

      expect(find.text('70.0%'), findsOneWidget); // 700 / 1000
      expect(find.text('30.0%'), findsOneWidget); // 300 / 1000
      expect(find.text('100.0%'), findsNothing);
    });

    testWidgets('矢印が年送りになり、送った先の年を読み直す', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);
      await tapPeriod(tester, '年');

      await tapIcon(tester, Icons.chevron_left);

      // ヘッダだけでなく中身も見る。ヘッダだけだと再取得漏れを見逃す
      expect(find.text('2025年'), findsOneWidget);
      expect(find.text('¥250'), findsWidgets);
      expect(find.text('¥1,000'), findsNothing);

      await tapIcon(tester, Icons.chevron_right);
      expect(find.text('2026年'), findsOneWidget);
      expect(find.text('¥1,000'), findsWidgets);
    });

    testWidgets('「今年に戻る」は今年では押せず、送った先では押せる', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);
      await tapPeriod(tester, '年');

      expect(find.byTooltip('今年に戻る'), findsOneWidget);
      expect(find.text('今年'), findsOneWidget);
      expect(find.text('今月'), findsNothing);
      expect(todayIsEnabled(tester), isFalse);

      await tapIcon(tester, Icons.chevron_left);
      expect(todayIsEnabled(tester), isTrue);

      await tester.tap(find.text('今年'));
      await tester.pumpAndSettle();
      expect(find.text('2026年'), findsOneWidget);
      expect(todayIsEnabled(tester), isFalse);
    });

    // 年送りで月まで動かすと、Provider を共有している割り勘タブの表示月が
    // 裏で動く。月モードへ戻したときに 7 月のままかで確かめる
    // 年送りは年の軸だけを動かす。表示月（＝割り勘タブと共有している年月）は
    // 1 年ぶんも動かない。ここが 2025年7月 になる実装だと、割り勘タブを開いた
    // 人の精算額が理由も分からず前の年のものに化ける
    testWidgets('年を送っても表示月は 1 年ぶんも動かない', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      await tapPeriod(tester, '年');
      await tapIcon(tester, Icons.chevron_left);
      await tapPeriod(tester, '月');

      expect(find.text('2026年7月'), findsOneWidget);
      expect(find.text('2025年7月'), findsNothing);
      // 中身も 7 月のまま
      expect(find.text('¥700'), findsWidgets);
    });

    // 年モードのテストはすべて表示月 7 月（= 今月）で動くので、
    // isCurrentYear と isCurrentMonth、goToCurrentYear と goToCurrentMonth が
    // 同じ結果になってしまう。表示月を今月から離して取り違えを炙り出す
    testWidgets('「今年に戻る」は表示月を今月に戻さない', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      // 表示月を 6 月にしてから年モードへ
      await tapIcon(tester, Icons.chevron_left);
      expect(find.text('2026年6月'), findsOneWidget);
      await tapPeriod(tester, '年');
      await tapIcon(tester, Icons.chevron_left);
      expect(find.text('2025年'), findsOneWidget);

      await tester.tap(find.text('今年'));
      await tester.pumpAndSettle();
      expect(find.text('2026年'), findsOneWidget);

      await tapPeriod(tester, '月');
      // goToCurrentMonth に取り違えるとここが 2026年7月 になる
      expect(find.text('2026年6月'), findsOneWidget);
    });

    // 受け入れ条件「取引のない月も 0 として X 軸に並ぶ」を画面レベルで見る。
    // ウィジェット単体のテストは「12 件渡したら 12 本」しか守らない
    testWidgets('12 か月ぶんをグラフに渡す（取引の無い月も 0 で）', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      await tapPeriod(tester, '年');

      final data = tester.widget<BarChart>(find.byType(BarChart)).data;
      expect(data.barGroups.length, 12);
      expect(data.barGroups.map((g) => g.barRods.single.toY), [
        0,
        0,
        300,
        0,
        0,
        0,
        700,
        0,
        0,
        0,
        0,
        0,
      ]);
    });
  });

  group('全期間モード', () {
    testWidgets('年別グラフだけを出し、期間の送りは消える', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      await tapPeriod(tester, '全期間');

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('年別の推移'), findsOneWidget);
      // 送る先が無いので期間ナビ自体を出さない
      expect(find.byType(MonthSelector), findsNothing);
      expect(find.widgetWithText(PageHeader, '全期間'), findsOneWidget);
      // 合計カードもカテゴリ別も出さない
      expect(find.byType(LedgerCard), findsNothing);
      expect(find.text('カテゴリ別'), findsNothing);
    });

    testWidgets('取引のある年だけが軸に並ぶ', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      await tapPeriod(tester, '全期間');

      final data = tester.widget<BarChart>(find.byType(BarChart)).data;
      expect(data.barGroups.length, 2);
      expect(data.barGroups.map((g) => g.barRods.single.toY), [250, 1000]);
    });

    // 全期間モードはグラフ 1 枚しかなく、中身が画面高より短い。
    // physics に AlwaysScrollableScrollPhysics を渡さないと、引っ張っても
    // RefreshIndicator が反応せず再取得できない
    testWidgets('中身が短くても引っ張って再取得できる', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);
      await tapPeriod(tester, '全期間');
      expect(
        tester.widget<BarChart>(find.byType(BarChart)).data.barGroups.length,
        2,
      );

      // 画面の外で 2024 年の取引が増えた状況を作る
      await seed(DateTime(2024, 5, 5), 100);

      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(
        tester.widget<BarChart>(find.byType(BarChart)).data.barGroups.length,
        3,
        reason: '引っ張っても再取得されていない',
      );
    });
  });

  group('期間セグメント', () {
    // selected を固定しても本文の切り替えは動き続けるので、
    // 「年を押したのにハイライトは月のまま」が本文のテストでは拾えない
    testWidgets('選択中の期間がハイライトに反映される', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      SummaryPeriod selected() =>
          tester
              .widget<SegmentedButton<SummaryPeriod>>(
                find.byType(SegmentedButton<SummaryPeriod>),
              )
              .selected
              .single;

      expect(selected(), SummaryPeriod.month);

      await tapPeriod(tester, '年');
      expect(selected(), SummaryPeriod.year);

      await tapPeriod(tester, '全期間');
      expect(selected(), SummaryPeriod.all);

      await tapPeriod(tester, '月');
      expect(selected(), SummaryPeriod.month);
    });
  });

  group('取引が 1 件も無いとき', () {
    // 受け入れ条件「取引が 1 件もない状態でも例外なく表示できる」
    testWidgets('3 モードすべてを踏んでも例外が出ない', (tester) async {
      await pumpSummary(tester);

      for (final label in ['年', '全期間', '月']) {
        await tapPeriod(tester, label);
        expect(tester.takeException(), isNull, reason: '$label モードで落ちた');
        // 見出しの下が無言の空白にならない
        expect(find.text('データがありません'), findsWidgets, reason: label);
      }
    });

    testWidgets('年モードでは推移グラフを描かず受け皿を出す', (tester) async {
      await pumpSummary(tester);

      await tapPeriod(tester, '年');

      // 12 か月すべて 0 なので棒を描かない
      expect(find.byType(BarChart), findsNothing);
      expect(find.text('月別の推移'), findsOneWidget);
      expect(find.text('データがありません'), findsWidgets);
    });
  });

  group('レイアウト', () {
    testWidgets('360px 幅で 3 つのセグメントが溢れない', (tester) async {
      await seedTwoYears();
      await pumpSummary(tester);

      for (final label in ['年', '全期間', '月']) {
        await tapPeriod(tester, label);
        expect(tester.takeException(), isNull, reason: '$label で overflow した');
      }
      expect(find.byType(SegmentedButton<SummaryPeriod>), findsOneWidget);
    });

    // 上限額でも崩れないこと。年モードは Y 軸に kMaxAmount 級の値が来る
    testWidgets('上限額の取引があっても年モードが崩れない', (tester) async {
      await seed(DateTime(2026, 3, 5), kMaxAmount);
      await pumpSummary(tester);

      await tapPeriod(tester, '年');

      expect(tester.takeException(), isNull);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('¥999,999,999,999'), findsWidgets);
    });
  });

  group('タブを移っても保たれる', () {
    // モードを画面の State に持たせると、ここで月モードに戻る。
    // MainScreen は IndexedStack を使わないので、タブを離れた時点で
    // SummaryScreen の State は破棄される
    testWidgets('取引タブへ移って戻っても年モードのまま', (tester) async {
      tester.view.physicalSize = const Size(360, 690);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedTwoYears();
      await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
      await tester.pumpAndSettle();

      await tapPeriod(tester, '年');
      expect(find.text('2026年'), findsOneWidget);

      await tester.tap(find.text('取引'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ホーム'));
      await tester.pumpAndSettle();

      expect(find.text('2026年'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('2026年7月'), findsNothing);
    });

    // 実測で踏んだ事故。年を送ったら割り勘タブが 2026年7月 / ¥700 から
    // 2025年7月 / ¥250 に化けていた。割り勘タブでは何も操作していないので、
    // 金額が変わった理由が画面から分からない
    testWidgets('サマリーで年を送っても割り勘タブの表示期間は動かない', (tester) async {
      tester.view.physicalSize = const Size(360, 690);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedTwoYears();
      await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
      await tester.pumpAndSettle();

      await tester.tap(find.text('割り勘'));
      await tester.pumpAndSettle();
      expect(find.text('2026年7月'), findsOneWidget);

      await tester.tap(find.text('ホーム'));
      await tester.pumpAndSettle();
      await tapPeriod(tester, '年');
      await tapIcon(tester, Icons.chevron_left);
      expect(find.text('2025年'), findsOneWidget);

      await tester.tap(find.text('割り勘'));
      await tester.pumpAndSettle();

      expect(find.text('2026年7月'), findsOneWidget);
      expect(find.text('2025年7月'), findsNothing);
      // 精算額も 7 月のまま
      expect(find.text('¥700'), findsWidgets);
      expect(find.text('¥250'), findsNothing);
    });
  });
}
