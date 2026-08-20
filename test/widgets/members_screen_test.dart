import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/models/transaction.dart';

/// メンバー画面で、削除できなかったことがユーザーに伝わるかを確かめる。
///
/// 見るのは 2 種類の「削除できない」。取引が残っているときの FK 違反
/// （例外が MemberProvider を素通りして SnackBar になる経路）と、
/// 最後の 1 人を消させないガード（例外ではなく画面側の早期 return）。
/// どちらも DB のテストでは代替できない。
void main() {
  late AppDatabase db;

  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// アプリを起動して、AppBar からメンバー管理画面へ push する
  Future<void> pumpMembersScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    expect(find.text('メンバー管理'), findsOneWidget);
  }

  /// [name] の行の削除ボタンを押す
  Future<void> tapDeleteOn(WidgetTester tester, String name) async {
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '削除'));
    await tester.pumpAndSettle();
  }

  const failureMessage = '削除できませんでした（取引が残っている可能性があります）';

  testWidgets('取引が残っているメンバーは削除できず、理由が SnackBar に出る', (tester) async {
    // 2 人にしておく。1 人だと「最後のメンバー」ガードで先に止まり、
    // FK 違反の経路まで届かない
    await db.insertMember('パートナー');
    final partner = (await db.getMembers()).firstWhere(
      (m) => m.name == 'パートナー',
    );
    final cats = await db.getCategories();
    await db.insertTransaction(
      TransactionInput(
        memberId: partner.id,
        categoryId: cats.first.id,
        amount: 1200,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ),
    );

    await pumpMembersScreen(tester);
    await tapDeleteOn(tester, 'パートナー');
    await confirmDelete(tester);

    expect(find.text(failureMessage), findsOneWidget);
    expect(find.text('パートナー'), findsOneWidget);
    expect((await db.getMembers()).map((m) => m.name), contains('パートナー'));
  });

  testWidgets('最後のメンバーは確認ダイアログすら出さずに拒否される', (tester) async {
    // 既定メンバーは onCreate で入る「自分」の 1 人だけ
    await pumpMembersScreen(tester);
    await tapDeleteOn(tester, '自分');

    expect(find.text('最後のメンバーは削除できません'), findsOneWidget);

    // ガードが showDialog より前にあることの固定。
    // 後ろに移すと「削除しますか？」に答えたあとで拒否される流れになる
    expect(find.text('メンバーを削除'), findsNothing);

    expect(find.text('自分'), findsOneWidget);
    expect((await db.getMembers()).map((m) => m.name), contains('自分'));
  });

  testWidgets('取引のないメンバーは削除でき、SnackBar は出ない', (tester) async {
    await db.insertMember('パートナー');

    await pumpMembersScreen(tester);
    await tapDeleteOn(tester, 'パートナー');
    await confirmDelete(tester);

    expect(find.text(failureMessage), findsNothing);
    expect(find.text('最後のメンバーは削除できません'), findsNothing);
    expect(find.text('パートナー'), findsNothing);
    expect(
      (await db.getMembers()).map((m) => m.name),
      isNot(contains('パートナー')),
    );
  });
}
