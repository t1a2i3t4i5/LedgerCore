import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/models/transaction.dart';

/// 取引の削除がサマリー・割り勘タブに反映されることを、タブ切り替え込みで確認する。
///
/// TransactionProvider と SummaryProvider は互いに通知を送らない。それでも
/// サマリーが最新に見えるのは、MainScreen がタブを単純差し替えしていて
/// 切り替えのたびに SummaryScreen が作り直され、initState で再取得するから。
/// この暗黙の依存が壊れると「削除したのにサマリーが古いまま」になるため、
/// タブを実際に往復して固定する。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('取引を削除するとサマリータブの合計に反映される', (tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 画面が表示する月を実時刻から切り離す（seed と表示で月がずれないように）
    final fixedNow = DateTime(2026, 7, 15);
    final cats = await db.getCategories();
    await db.insertMember('パートナー');
    final members = await db.getMembers();
    final me = members.firstWhere((m) => m.name == '自分').id;
    final partner = members.firstWhere((m) => m.name == 'パートナー').id;

    // 合計カードもカテゴリ別・メンバー別の行も同じ '¥{金額}' 形式なので、
    // 合計値が個別の金額と衝突しないように 3 件を 2 メンバーへ散らす。
    //   合計 5000 / カテゴリ別 1200・3500・300 / メンバー別 1500・3500
    //   削除後 3800 / カテゴリ別 3500・300 / メンバー別 300・3500
    //
    // カテゴリ別の行には構成比も付くが、金額とは別の Text に分かれているので
    // （summary_screen.dart の trailing は Column）この衝突の勘定は変わらない。
    Future<void> seed(int memberId, int categoryIndex, double amount) =>
        db.insertTransaction(
          TransactionInput(
            memberId: memberId,
            categoryId: cats[categoryIndex].id,
            amount: amount,
            spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
          ),
        );
    await seed(me, 0, 1200); // 食費
    await seed(partner, 1, 3500); // 日用品
    await seed(me, 2, 300); // 交通費

    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();

    // 初期表示はサマリータブ
    expect(find.text('¥5,000'), findsOneWidget);

    // 取引タブで食費を削除する
    await tester.tap(find.text('取引'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('食費'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    expect(find.text('食費'), findsNothing);

    // サマリータブへ戻ると再集計されている
    await tester.tap(find.text('サマリー'));
    await tester.pumpAndSettle();

    expect(find.text('¥3,800'), findsOneWidget);
    expect(find.text('¥5,000'), findsNothing);
  });
}
