import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/split_screen.dart';
import 'package:provider/provider.dart';

/// テキストが横幅に収まらず ellipsis で畳まれたかどうか。
/// `find.text()` は畳まれた Text にもマッチするので `findsOneWidget` では守れない。
bool _isEllipsized(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

/// メンバーの行に、支払済みと過不足が**同じ `ListTile` の中に**出ていること。
/// 画面全体に対する `find.text()` では、行と行で中身が入れ替わっても通ってしまう。
void expectMemberRow(
  WidgetTester tester,
  String memberName, {
  required String paid,
  required String balance,
  required String label,
}) {
  final tile = find.ancestor(
    of: find.text(memberName),
    matching: find.byType(ListTile),
  );
  expect(tile, findsOneWidget, reason: '$memberName の行が無い');
  for (final expected in [paid, balance, label]) {
    expect(
      find.descendant(of: tile, matching: find.text(expected)),
      findsOneWidget,
      reason: '$memberName の行に $expected が無い',
    );
  }
}

/// 割り勘画面を、インメモリ DB 込みで確認する。実端末のファイルには触らない。
void main() {
  late AppDatabase db;

  // 表示月を実時刻から切り離す（seed と表示で月がずれないように）
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpSplit(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SummaryProvider(db, clock: () => fixedNow),
        child: const MaterialApp(home: Scaffold(body: SplitScreen())),
      ),
    );
    // initState の postFrameCallback で fetch が走るので落ち着かせる
    await tester.pumpAndSettle();
  }

  /// 名前を指定してメンバーを足し、その id を返す。
  Future<int> addMember(String name) async {
    await db.insertMember(name);
    return (await db.getMembers()).firstWhere((m) => m.name == name).id;
  }

  Future<void> addTransaction(int memberId, double amount) async {
    final cats = await db.getCategories();
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: cats.first.id,
        amount: amount,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ),
    );
  }

  /// 既定メンバー「自分」を外して、名前をこちらで決めた 2 人に揃える。
  Future<void> replaceMembersWith(String a, String b) async {
    for (final m in await db.getMembers()) {
      await db.deleteMember(m.id);
    }
    await addMember(a);
    await addMember(b);
  }

  testWidgets('メンバーごとに支払済みと過不足が同じ行に並ぶ', (tester) async {
    final me = (await db.getMembers()).first.id;
    await addMember('パートナー');
    await addTransaction(me, 3000);

    await pumpSplit(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('¥3,000'), findsOneWidget); // 合計
    expect(find.text('¥1,500'), findsOneWidget); // 一人当たり
    expectMemberRow(
      tester,
      '自分',
      paid: '支払済み: ¥3,000',
      balance: '+¥1,500',
      label: '受け取り',
    );
    expectMemberRow(
      tester,
      'パートナー',
      paid: '支払済み: ¥0',
      balance: '¥-1,500',
      label: '支払い',
    );
    expect(find.text('パートナー → 自分 に 1500 円支払う'), findsOneWidget);
  });

  // 金額は ListTile の trailing に入る。桁が伸びると title のメンバー名が
  // 黙って畳まれる（例外も出ず find.text() も通る）
  testWidgets('上限額でもメンバー名が畳まれない', (tester) async {
    // 既定カテゴリのような 2〜3 文字では、幅が足りない実装でも収まってしまう
    await replaceMembersWith('ながいなまえ', 'もうひとり');
    final ms = await db.getMembers();
    await addTransaction(ms.first.id, kMaxAmount);

    await pumpSplit(tester);

    expect(tester.takeException(), isNull);
    expect(_isEllipsized(tester, 'ながいなまえ'), isFalse, reason: 'メンバー名が畳まれた');

    // 2 人目は ListView のビューポート外に居ることがあるので、送ってから見る
    await tester.scrollUntilVisible(find.text('もうひとり'), 100);
    expect(_isEllipsized(tester, 'もうひとり'), isFalse, reason: 'メンバー名が畳まれた');
  });

  // 合計と一人当たりは Row の中で幅を折半する。桁が伸びたときにはみ出さないこと
  testWidgets('上限額でも合計カードがはみ出さない', (tester) async {
    final me = (await db.getMembers()).first.id;
    await addMember('パートナー');
    await addTransaction(me, kMaxAmount);

    await pumpSplit(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('¥999,999,999,999'), findsWidgets);
    expect(_isEllipsized(tester, '¥999,999,999,999'), isFalse);
  });

  // 取引ゼロの月でも split は空の結果が返る（null にはならない）ので、
  // 「データがありません」ではなく ¥0 の割り勘が出る
  testWidgets('取引が無い月は合計 ¥0 と精算不要を出す', (tester) async {
    await addMember('パートナー');

    await pumpSplit(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('データがありません'), findsNothing);
    expect(find.text('¥0'), findsWidgets);
    expect(find.text('精算不要'), findsOneWidget);
    expectMemberRow(tester, '自分', paid: '支払済み: ¥0', balance: '¥0', label: '均等');
  });
}
