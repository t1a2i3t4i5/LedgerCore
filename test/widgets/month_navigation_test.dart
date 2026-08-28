import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/split_screen.dart';
import 'package:ledger_app/screens/summary_screen.dart';
import 'package:ledger_app/screens/transactions_screen.dart';
import 'package:provider/provider.dart';

/// 取引・サマリー・割り勘の 3 画面の月送りが、実際にタップして動くことを見る。
///
/// 月送りのロジック自体は month_scoped_provider_test.dart で担保しているが、
/// それだけだと「Provider は正しいが画面の配線が間違っている」を拾えない。
/// 実際、左右の矢印を入れ替えても Provider のテストは全部通る。
/// 月選択の Row 自体は [MonthSelector] に集約したが、それを 3 画面がどう
/// 呼んでいるか（どの Provider を渡し、どのコールバックを結んだか）は画面ごとに
/// 違うので、3 画面ぶん見る。[MonthSelector] 単体の挙動は
/// month_selector_test.dart が担当する。
void main() {
  late AppDatabase db;

  // 表示月を実時刻から切り離す。この月が「今月」になる
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// 月ごとに違う金額を入れる。金額で「どの月を読んでいるか」が判別できる
  Future<void> seed(int year, int month, double amount) async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(
      TransactionInput(
        memberId: members.first.id,
        categoryId: cats.first.id,
        amount: amount,
        spentAt: DateTime(year, month, 5),
      ),
    );
  }

  /// 6 月 = 600、7 月（今月）= 700、8 月 = 800
  Future<void> seedThreeMonths() async {
    await seed(2026, 6, 600);
    await seed(2026, 7, 700);
    await seed(2026, 8, 800);
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider(create: (_) => MemberProvider(db)),
          ChangeNotifierProvider(
            create: (_) => TransactionProvider(db, clock: () => fixedNow),
          ),
          ChangeNotifierProvider(
            create: (_) => SummaryProvider(db, clock: () => fixedNow),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  /// 「今月に戻る」ボタンが押せる状態か
  bool todayEnabled(WidgetTester tester) =>
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.text('今月'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;

  /// 3 画面に共通の月送りの検証。[amountOf] は月ごとに画面へ出る金額の文字列
  void monthNavigationTests(
    String label,
    Widget Function() buildScreen,
    String Function(int month) amountOf,
  ) {
    group(label, () {
      testWidgets('初期表示は clock の月で、その月のデータが出る', (tester) async {
        await seedThreeMonths();
        await pump(tester, buildScreen());

        expect(find.text('2026年7月'), findsOneWidget);
        expect(find.text(amountOf(7)), findsWidgets);
      });

      testWidgets('左の矢印で前月へ動き、前月のデータを読み直す', (tester) async {
        await seedThreeMonths();
        await pump(tester, buildScreen());

        await tapIcon(tester, Icons.chevron_left);

        // ヘッダだけでなく中身も見る。ヘッダだけだと「月表示は動いたが
        // 再取得していない」を見逃す
        expect(find.text('2026年6月'), findsOneWidget);
        expect(find.text(amountOf(6)), findsWidgets);
        expect(find.text(amountOf(7)), findsNothing);
      });

      testWidgets('右の矢印で翌月へ動き、翌月のデータを読み直す', (tester) async {
        await seedThreeMonths();
        await pump(tester, buildScreen());

        await tapIcon(tester, Icons.chevron_right);

        expect(find.text('2026年8月'), findsOneWidget);
        expect(find.text(amountOf(8)), findsWidgets);
        expect(find.text(amountOf(7)), findsNothing);
      });

      testWidgets('今月に戻るボタンは今月では押せず、送った先では押せる', (tester) async {
        await seedThreeMonths();
        await pump(tester, buildScreen());

        expect(todayEnabled(tester), isFalse);

        await tapIcon(tester, Icons.chevron_left);
        expect(todayEnabled(tester), isTrue);
      });

      testWidgets('今月に戻るボタンで clock の月へ戻り、その月を読み直す', (tester) async {
        await seedThreeMonths();
        await pump(tester, buildScreen());
        await tapIcon(tester, Icons.chevron_left);
        expect(find.text('2026年6月'), findsOneWidget);

        await tester.tap(find.text('今月'));
        await tester.pumpAndSettle();

        expect(find.text('2026年7月'), findsOneWidget);
        expect(find.text(amountOf(7)), findsWidgets);
        expect(todayEnabled(tester), isFalse);
      });

      testWidgets('12 月から翌月へ送ると翌年 1 月になる', (tester) async {
        await seed(2027, 1, 100);
        await pump(tester, buildScreen());

        // 7 月 → 12 月まで 5 回送る
        for (var i = 0; i < 5; i++) {
          await tapIcon(tester, Icons.chevron_right);
        }
        expect(find.text('2026年12月'), findsOneWidget);

        await tapIcon(tester, Icons.chevron_right);

        expect(find.text('2027年1月'), findsOneWidget);
      });
    });
  }

  // 取引一覧は合計パネルの金額部分に '¥700' の形で出る
  monthNavigationTests(
    '取引一覧画面',
    () => const TransactionsScreen(),
    (month) => '¥${month}00',
  );

  // サマリー・割り勘は合計カードに '¥700' の形で出る
  monthNavigationTests(
    'サマリー画面',
    () => const SummaryScreen(),
    (month) => '¥${month}00',
  );

  monthNavigationTests(
    '割り勘画面',
    () => const SplitScreen(),
    (month) => '¥${month}00',
  );
}
