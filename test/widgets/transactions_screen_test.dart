import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/transactions_screen.dart';
import 'package:provider/provider.dart';

/// 取引一覧画面からの削除フロー（長押し → 確認ダイアログ）を確認する。
///
/// Provider の状態遷移は transaction_provider_test.dart 側で担保しており、
/// ここでは「ダイアログを経由して初めて消える」ことと、
/// 合計パネル・空状態の表示が削除に追随することを見る。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// 今月の [day] 日に [amount] の取引を入れる。
  ///
  /// 画面は DateTime.now() の年月を初期表示するので、
  /// テストデータは必ず今月に置く。
  Future<String> seedTransaction({
    required double amount,
    int day = 5,
    int categoryIndex = 0,
  }) async {
    final now = DateTime.now();
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(TransactionRequest(
      userId: members.first.id,
      categoryId: cats[categoryIndex].id,
      amount: amount,
      spentAt: DateTime(now.year, now.month, day),
    ));
    return cats[categoryIndex].name;
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider(create: (_) => MemberProvider(db)),
          ChangeNotifierProvider(create: (_) => TransactionProvider(db)),
        ],
        // TransactionsScreen は自前で Scaffold を返す
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    // initState の postFrameCallback で取引・カテゴリ・メンバーを読む
    await tester.pumpAndSettle();
  }

  testWidgets('長押しで確認ダイアログが出る', (tester) async {
    final categoryName = await seedTransaction(amount: 1200);
    await pumpScreen(tester);

    await tester.longPress(find.text(categoryName));
    await tester.pumpAndSettle();

    expect(find.text('取引を削除'), findsOneWidget);
    expect(find.text('この取引を削除しますか？'), findsOneWidget);
    expect(find.text('キャンセル'), findsOneWidget);
  });

  testWidgets('キャンセルすると削除されない', (tester) async {
    final categoryName = await seedTransaction(amount: 1200);
    await pumpScreen(tester);

    await tester.longPress(find.text(categoryName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(find.text('取引を削除'), findsNothing);
    expect(find.text(categoryName), findsOneWidget);
    expect(find.text('1件'), findsOneWidget);
    // DB からも消えていない
    expect(await db.getAllTransactions(), hasLength(1));
  });

  testWidgets('削除を選ぶと一覧と DB から消える', (tester) async {
    final categoryName = await seedTransaction(amount: 1200);
    await seedTransaction(amount: 3500, day: 6, categoryIndex: 1);
    await pumpScreen(tester);
    expect(find.text('2件'), findsOneWidget);

    await tester.longPress(find.text(categoryName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect(find.text(categoryName), findsNothing);
    expect(find.text('1件'), findsOneWidget);
    expect(await db.getAllTransactions(), hasLength(1));
  });

  testWidgets('削除すると合計パネルの金額が減る', (tester) async {
    final categoryName = await seedTransaction(amount: 1200);
    await seedTransaction(amount: 3500, day: 6, categoryIndex: 1);
    await pumpScreen(tester);
    expect(find.text('合計 ¥4,700'), findsOneWidget);

    await tester.longPress(find.text(categoryName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect(find.text('合計 ¥3,500'), findsOneWidget);
  });

  testWidgets('最後の1件を削除すると空状態メッセージが出る', (tester) async {
    final categoryName = await seedTransaction(amount: 1200);
    await pumpScreen(tester);

    await tester.longPress(find.text(categoryName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    // フィルター中の '該当する取引がありません' ではなく、
    // 取引そのものが無いときの文言が出る
    expect(find.text('取引がありません'), findsOneWidget);
    expect(find.text('該当する取引がありません'), findsNothing);
    expect(find.text('0件'), findsOneWidget);
    // NumberFormat('#,###') は 0 を空文字にせず '0' を返す
    expect(find.text('合計 ¥0'), findsOneWidget);
  });
}
