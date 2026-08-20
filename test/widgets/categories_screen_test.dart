import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/models/transaction.dart';

/// カテゴリ画面で、削除できなかったことがユーザーに伝わるかを確かめる。
///
/// FK 違反そのものは test/database_test.dart が DAO 直叩きで押さえているが、
/// それは「DB が弾く」ところまでしか見ていない。この画面の問題は、例外が
/// Provider を素通りして SnackBar になるまでの経路のほうにある。
/// CategoryProvider.delete を握りつぶしに書き換えても DB のテストは全部通り、
/// 「削除できていないのに成功したように見える」退行を誰も止められない。
void main() {
  late AppDatabase db;

  // 表示月を実時刻から切り離す（seed した取引が「今月」に依存しないように）
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// アプリを起動してカテゴリタブまで移動する
  Future<void> pumpCategoriesTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();

    // 起動直後はサマリータブ。label_outline はサマリー画面のカテゴリ別リストの
    // leading にもあるので（実測で 2 件ヒットした）、ボトムナビの中に限って探す
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.label_outline),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// [name] の行の削除ボタンを押す。
  ///
  /// delete_outline は行数ぶんあるので、対象の ListTile の中に限って探す
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

  /// 確認ダイアログの「削除」を押す
  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '削除'));
    await tester.pumpAndSettle();
  }

  const failureMessage = '削除できませんでした（取引が残っている可能性があります）';

  testWidgets('取引が残っているカテゴリは削除できず、理由が SnackBar に出る', (tester) async {
    // 既定カテゴリは onCreate で 10 件入る。末尾は 690px の画面からはみ出して
    // タップが届かないので、先頭（食費）を対象にする
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(
      TransactionInput(
        memberId: members.first.id,
        categoryId: cats.first.id,
        amount: 1200,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ),
    );

    await pumpCategoriesTab(tester);
    await tapDeleteOn(tester, cats.first.name);
    await confirmDelete(tester);

    // 握りつぶし退行を殺すのはこの 1 行。DB が弾いても画面が黙っていたら通らない
    expect(find.text(failureMessage), findsOneWidget);

    // 一覧にも残り続ける
    expect(find.text(cats.first.name), findsOneWidget);
    expect(
      (await db.getCategories()).map((c) => c.name),
      contains(cats.first.name),
    );
  });

  testWidgets('取引のないカテゴリは削除でき、SnackBar は出ない', (tester) async {
    // 失敗ケースだけだと「常に失敗の SnackBar を出す」実装でも緑になるので、
    // 成功パスを対照として固定する
    final cats = await db.getCategories();
    final target = cats[1];

    await pumpCategoriesTab(tester);
    await tapDeleteOn(tester, target.name);
    await confirmDelete(tester);

    expect(find.text(failureMessage), findsNothing);
    expect(find.text(target.name), findsNothing);
    expect(
      (await db.getCategories()).map((c) => c.name),
      isNot(contains(target.name)),
    );
  });
}
