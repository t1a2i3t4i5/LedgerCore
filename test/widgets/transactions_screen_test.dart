import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/transactions_screen.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/amount_format.dart';
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:provider/provider.dart';

/// テキストが横幅に収まらず ellipsis で畳まれたかどうか。
bool _isEllipsized(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

/// 取引一覧画面からの削除フロー（長押し → 確認ダイアログ）を確認する。
///
/// Provider の状態遷移は transaction_provider_test.dart 側で担保しており、
/// ここでは「ダイアログを経由して初めて消える」ことと、
/// 合計パネル・空状態の表示が削除に追随することを見る。
void main() {
  late AppDatabase db;

  // 画面が表示する月を実時刻から切り離す。TransactionProvider には
  // この時刻を返す clock を注入するので、seed とテストの間で
  // 月が変わっても（月末 23:59 台の CI など）結果は変わらない
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// 表示対象月（fixedNow の月）の [day] 日に [amount] の取引を入れる
  Future<String> seedTransaction({
    required double amount,
    int day = 5,
    int categoryIndex = 0,
    String? categoryName,
    String? memo,
  }) async {
    if (categoryName != null) await db.insertCategory(categoryName);
    final cats = await db.getCategories();
    final members = await db.getMembers();
    final category =
        categoryName == null
            ? cats[categoryIndex]
            : cats.singleWhere((category) => category.name == categoryName);
    await db.insertTransaction(
      TransactionInput(
        memberId: members.first.id,
        categoryId: category.id,
        amount: amount,
        spentAt: DateTime(fixedNow.year, fixedNow.month, day),
        memo: memo,
      ),
    );
    return category.name;
  }

  Future<void> pumpScreen(WidgetTester tester, {String? memoFilter}) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider(create: (_) => MemberProvider(db)),
          ChangeNotifierProvider(
            create:
                (_) =>
                    TransactionProvider(db, clock: () => fixedNow)
                      ..setFilters(memoQuery: memoFilter),
          ),
        ],
        // TransactionsScreen は自前で Scaffold を返す
        child: MaterialApp(
          theme: ledgerTheme,
          home: const TransactionsScreen(),
        ),
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

  testWidgets('ダイアログ外をタップして閉じても削除されない', (tester) async {
    final categoryName = await seedTransaction(amount: 1200);
    await pumpScreen(tester);

    await tester.longPress(find.text(categoryName));
    await tester.pumpAndSettle();
    // バリアをタップして閉じると showDialog<bool> は null を返す。
    // 実装が `confirmed == true` ではなく `confirmed != false` だと
    // ここで削除が走ってしまう
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('取引を削除'), findsNothing);
    expect(find.text(categoryName), findsOneWidget);
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
    expect(find.text('合計'), findsOneWidget);
    expect(find.text('¥4,700'), findsOneWidget);

    await tester.longPress(find.text(categoryName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect(find.text('合計'), findsOneWidget);
    expect(find.text('¥3,500'), findsNWidgets(2));
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
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.text('0件'), findsOneWidget);
    // formatYen() の書式 '#,###' は 0 を空文字にせず '0' を返す
    expect(find.text('合計'), findsOneWidget);
    expect(find.text('¥0'), findsOneWidget);
  });

  testWidgets('フィルター結果が空のときも新しい空状態を描く', (tester) async {
    await seedTransaction(amount: 1200, memo: 'スーパー');
    await pumpScreen(tester, memoFilter: '該当なし');

    expect(find.text('該当する取引がありません'), findsOneWidget);
    expect(find.text('取引がありません'), findsNothing);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
  });

  testWidgets('カテゴリ色のドットと日付・メンバー・メモを同じ行に描く', (tester) async {
    final categoryName = await seedTransaction(
      amount: 1200,
      day: 18,
      memo: 'スーパー',
    );
    final category = (await db.getCategories()).singleWhere(
      (category) => category.name == categoryName,
    );
    final memberName = (await db.getMembers()).first.name;
    await pumpScreen(tester);

    final tile = find.ancestor(
      of: find.text(categoryName),
      matching: find.byType(ListTile),
    );
    final dot = tester.widget<CircleAvatar>(
      find.descendant(of: tile, matching: find.byType(CircleAvatar)),
    );
    expect(dot.backgroundColor, categoryColor(category.id));
    expect(dot.child, isNull);
    expect(
      find.descendant(
        of: tile,
        matching: find.text('7/18 · $memberName · スーパー'),
      ),
      findsOneWidget,
    );

    final subtitle = tester.widget<Text>(
      find.descendant(
        of: tile,
        matching: find.text('7/18 · $memberName · スーパー'),
      ),
    );
    expect(subtitle.style?.color, ledgerTheme.colorScheme.onSurfaceVariant);
    final spans = (subtitle.textSpan! as TextSpan).children!;
    expect((spans.first as TextSpan).style?.color, LedgerTokens.subtext);
    expect((spans.last as TextSpan).style, isNull);
  });

  testWidgets('取引行と合計パネルの金額は amountRow を使う', (tester) async {
    await seedTransaction(amount: 1200);
    await pumpScreen(tester);

    final amounts = tester.widgetList<Text>(find.text('¥1,200')).toList();
    expect(amounts, hasLength(2));
    for (final amount in amounts) {
      expect(amount.style, LedgerTokens.amountRow);
    }
  });

  testWidgets('フィルター件数バッジはアクセント色を使う', (tester) async {
    await pumpScreen(tester, memoFilter: '該当なし');

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.backgroundColor, ledgerTheme.colorScheme.secondary);
    expect(badge.textColor, ledgerTheme.colorScheme.onSurface);
    expect(badge.isLabelVisible, isTrue);
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('1')),
      findsOneWidget,
    );
  });

  // kMaxAmount は「保存できる値」として DB の CHECK が認めている。
  // 短い金額しか描かないと、実機幅で最大金額が overflow するのを見逃す。
  // 金額はリテラルで持たず kMaxAmount から採る（上限を変えたら追随させる）。
  testWidgets('上限いっぱいの金額でも一覧と合計パネルが overflow しない', (tester) async {
    await seedTransaction(amount: kMaxAmount);
    await pumpScreen(tester);

    // 一覧の行と合計パネルの両方に最大金額が出る状態にする
    final formatted = formatYen(kMaxAmount);
    expect(find.text(formatted), findsNWidgets(2));
    expect(_isEllipsized(tester, '食費'), isFalse);
    // overflow は例外として記録されるので、握りつぶさず明示的に見る
    expect(tester.takeException(), isNull);
  });

  // 合計は 1 件あたりの上限より長くなる。上限額の行を並べるほど桁が増えるので、
  // 「1 件だけ最大」より合計パネルが厳しくなる
  testWidgets('上限いっぱいの取引が複数あっても合計パネルが overflow しない', (tester) async {
    await seedTransaction(amount: kMaxAmount);
    await seedTransaction(amount: kMaxAmount, day: 6, categoryIndex: 1);
    await pumpScreen(tester);

    final total = formatYen(kMaxAmount * 2);
    expect(find.text(total), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上限金額と50文字カテゴリ名でも overflow しない', (tester) async {
    final categoryName = 'あ' * 50;
    await seedTransaction(
      amount: kMaxAmount,
      categoryName: categoryName,
      memo: 'スーパー',
    );
    await pumpScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(categoryName), findsOneWidget);
    expect(_isEllipsized(tester, categoryName), isTrue);
    // 金額領域を広げすぎると ListTile が title の幅を 0 にしてしまう。
    // find.text() は幅 0 でも見つけるため、描画幅も直接見る。
    expect(tester.getSize(find.text(categoryName)).width, greaterThan(0));
    expect(find.text('7/5 · 自分 · スーパー'), findsOneWidget);
    expect(_isEllipsized(tester, '7/5 · 自分 · スーパー'), isTrue);
  });
}
