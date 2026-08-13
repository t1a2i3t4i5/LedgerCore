import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/transaction_filter_sheet.dart';
import 'package:ledger_app/widgets/amount_input_formatter.dart';
import 'package:provider/provider.dart';

/// フィルターシートが「適用」「リセット」で Provider に何を書くかを確認する。
///
/// 前半は金額欄が取引追加画面と同じ挙動になっていること。フィルタの入力値は
/// DB に保存されないので CHECK 制約では守られない。同じアプリ内で入力の
/// 受け付け方が割れていると、「追加画面では全角がそのまま通るのに、
/// フィルターでは理由の分からないエラーになる」という食い違いが出る。
///
/// 後半は金額欄以外の適用経路（ソート・カテゴリ・登録者・メモ・リセット）。
/// ここが無い間は `_apply` の `setSort` と `_reset` の `resetFilters` を
/// 両方消しても全件グリーンのままだった。
void main() {
  late AppDatabase db;
  late TransactionProvider provider;

  // 表示月を実時刻から切り離す。ソートの検証で取引を seed するので、
  // 「今月」に置くと月末 23:59 台の実行で seed と表示月がずれる
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = TransactionProvider(db, clock: () => fixedNow);
  });
  tearDown(() async => db.close());

  /// 表示対象月の [day] 日に [amount] の取引を入れる
  Future<void> seedTransaction({
    required double amount,
    int day = 5,
    int categoryIndex = 0,
    int memberIndex = 0,
    String? memo,
  }) async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(TransactionInput(
      memberId: members[memberIndex].id,
      categoryId: cats[categoryIndex].id,
      amount: amount,
      spentAt: DateTime(fixedNow.year, fixedNow.month, day),
      memo: memo,
    ));
  }

  /// 実画面と同じく `showModalBottomSheet` で開く。
  ///
  /// シートを直接 `home` に置くと、`_apply` の `Navigator.pop()` が唯一のルートを
  /// 外してツリーが空になる。その状態では `find.text(...)` が何に対しても
  /// `findsNothing` になり、「エラーが出ていないこと」を見るアサーションが
  /// 無条件に通ってしまう（実際、成功パスに `_showError` を差し込んでも通った）。
  /// シートの下に画面を残しておけば、pop 後も SnackBar を検出できる。
  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 実画面では一覧を開いた時点でどちらも読み込み済み。生成しただけの
    // Provider を渡すと一覧が空のまま「カテゴリがありません」だけが出て、
    // FilterChip が 1 つも描かれずチップの経路を通せない
    final categoryProvider = CategoryProvider(db);
    final memberProvider = MemberProvider(db);
    await categoryProvider.fetch();
    await memberProvider.fetchMembers();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: categoryProvider),
          ChangeNotifierProvider.value(value: memberProvider),
          ChangeNotifierProvider.value(value: provider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const TransactionFilterSheet(),
                ),
                child: const Text('シートを開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('シートを開く'));
    await tester.pumpAndSettle();
  }

  /// シートはカテゴリ 10 件・登録者のチップを含んで縦に長く、360x690 では
  /// 下端のボタンが可視域の外にある。`tap` は画面外だと warnIfMissed で
  /// 落ちるので、押す前に必ずスクロールで送り込む
  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder minField() => find.widgetWithText(TextFormField, '最小 (¥)');
  Finder maxField() => find.widgetWithText(TextFormField, '最大 (¥)');
  Finder memoField() =>
      find.widgetWithText(TextFormField, 'メモに含まれる文字列');

  // ---- 金額欄 ----

  testWidgets('全角数字は半角に直して受け付ける', (tester) async {
    await pumpSheet(tester);

    // 従来は正規化が無く、double.tryParse が null を返して
    // 「最小金額が不正な値です」とだけ出ていた
    await tester.enterText(minField(), '１０００');
    await tester.pump();

    await tapInSheet(tester, find.text('適用'));

    expect(find.text('最小金額が不正な値です'), findsNothing);
    expect(provider.filterMinAmount, 1000);
  });

  testWidgets('小数点とマイナス記号は入力自体を受け付けない', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(minField(), '-1234.5');
    await tester.pump();

    expect(find.text('-1234.5'), findsNothing);
    expect(find.text('12345'), findsOneWidget);
  });

  testWidgets('桁を打ち続けても上限の桁数で打ち切られる', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(maxField(), '9' * 400);
    await tester.pump();

    // 期待値はリテラルで持たない。上限を変えたときに追随させる
    final field = tester.widget<TextField>(
      find.descendant(of: maxField(), matching: find.byType(TextField)),
    );
    expect(field.controller!.text, '9' * maxAmountInputLength);
  });

  testWidgets('設定済みの条件が復元され、打ち替えた分だけ適用される', (tester) async {
    provider.setFilters(
      categoryIds: const {},
      memberIds: const {},
      minAmount: 1234,
      maxAmount: 5678,
      memoQuery: '',
    );

    await pumpSheet(tester);
    // 開いた時点の表示（復元経路）
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('5678'), findsOneWidget);

    // 事前値と違う値に打ち替えてから適用する。
    // 事前値のまま「触らずに適用」を検証すると、_apply が Provider に一切
    // 書き戻さなくても事前値が残って通ってしまい、往復を検証できない
    await tester.enterText(minField(), '2345');
    await tapInSheet(tester, find.text('適用'));

    expect(provider.filterMinAmount, 2345);
    // 触っていない側は復元された値がそのまま往復する
    expect(provider.filterMaxAmount, 5678);
  });

  // フォーマッタは composing 中（IME の変換確定前）を素通しする。これは IME を
  // 壊さないための仕様なので、桁数制限を抜けた値がコントローラに入りうる。
  // 400 桁は double.tryParse が Infinity として解釈するため、null チェックだけの
  // バリデーションでは止まらない。Infinity が入ると全件が除外され、開き直すと
  // 欄に 'Infinity' が表示され、再適用しても同じ状態のまま固定される。
  testWidgets('composing 中に送られた桁あふれは適用されない', (tester) async {
    await pumpSheet(tester);
    await tester.tap(minField());
    await tester.pump();

    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: '9' * 400,
      selection: const TextSelection.collapsed(offset: 400),
      composing: const TextRange(start: 0, end: 400),
    ));
    await tester.pump();

    await tapInSheet(tester, find.text('適用'));

    expect(find.text('最小金額が不正な値です'), findsOneWidget);
    expect(provider.filterMinAmount, isNull);
  });

  testWidgets('上限を超える値は適用されない', (tester) async {
    await pumpSheet(tester);
    await tester.tap(minField());
    await tester.pump();

    // 桁数制限を抜ける経路（composing）で上限超過の有限値を送る
    final over = (kMaxAmount + 1).toStringAsFixed(0);
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: over,
      selection: TextSelection.collapsed(offset: over.length),
      composing: TextRange(start: 0, end: over.length),
    ));
    await tester.pump();

    await tapInSheet(tester, find.text('適用'));

    expect(find.text('最小金額が不正な値です'), findsOneWidget);
    expect(provider.filterMinAmount, isNull);
  });

  testWidgets('最小が最大より大きいと適用されない', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(minField(), '5000');
    await tester.enterText(maxField(), '1000');
    await tapInSheet(tester, find.text('適用'));

    expect(find.text('最小金額は最大金額以下にしてください'), findsOneWidget);
    expect(provider.filterMinAmount, isNull);
  });

  testWidgets('金額欄を空にして適用するとフィルタが外れる', (tester) async {
    provider.setFilters(
      categoryIds: const {},
      memberIds: const {},
      minAmount: 1000,
      maxAmount: 5000,
      memoQuery: '',
    );

    await pumpSheet(tester);
    expect(find.text('1000'), findsOneWidget);

    await tester.enterText(minField(), '');
    await tester.enterText(maxField(), '');
    await tapInSheet(tester, find.text('適用'));

    expect(provider.filterMinAmount, isNull);
    expect(provider.filterMaxAmount, isNull);
    expect(provider.activeFilterCount, 0);
  });

  // ---- ソート ----

  testWidgets('適用でソートのフィールドと並び順が反映される', (tester) async {
    // 日付の昇順と金額の昇順が別の並びになるように置く。
    // 同じ並びだと、フィールドを無視して order だけ見る実装でも通る
    await seedTransaction(amount: 3000, day: 3);
    await seedTransaction(amount: 1000, day: 10);
    await provider.fetch();

    await pumpSheet(tester);

    // 初期値は日付・降順。両方とも違う値へ打ち替える
    await tapInSheet(tester, find.text('金額'));
    await tapInSheet(tester, find.byTooltip('降順'));
    await tapInSheet(tester, find.text('適用'));

    expect(provider.sortField, TransactionSortField.amount);
    expect(provider.sortOrder, SortOrder.asc);
    // 状態だけでなく、一覧に出る順番まで見る
    expect(
      provider.filteredTransactions.map((t) => t.amount).toList(),
      [1000, 3000],
    );
  });

  // ---- カテゴリ・登録者・メモ ----

  testWidgets('選んだカテゴリチップが適用される', (tester) async {
    // id はリテラルで持たない。既定カテゴリの並びが変わっても追随させる
    final cats = await db.getCategories();
    final target = cats.firstWhere((c) => c.name == '交通費');

    await pumpSheet(tester);
    await tapInSheet(tester, find.widgetWithText(FilterChip, '交通費'));
    await tapInSheet(tester, find.text('適用'));

    expect(provider.filterCategoryIds, {target.id});
  });

  testWidgets('選んだ登録者チップが適用される', (tester) async {
    // 既定の「自分」だけだと、選択に関係なく先頭を入れる実装でも通ってしまう
    await db.insertMember('配偶者');
    final members = await db.getMembers();
    final target = members.firstWhere((m) => m.name == '配偶者');

    await pumpSheet(tester);
    await tapInSheet(tester, find.widgetWithText(FilterChip, '配偶者'));
    await tapInSheet(tester, find.text('適用'));

    expect(provider.filterMemberIds, {target.id});
  });

  testWidgets('メモ検索は前後の空白を落として適用される', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(memoField(), '  コンビニ  ');
    await tapInSheet(tester, find.text('適用'));

    expect(provider.filterMemoQuery, 'コンビニ');
  });

  // ---- リセット ----

  testWidgets('リセットで全てのフィルタが解除される', (tester) async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    provider.setFilters(
      categoryIds: {cats.first.id},
      memberIds: {members.first.id},
      minAmount: 1000,
      maxAmount: 5000,
      memoQuery: 'コンビニ',
    );
    // 解除される前に全種類が立っていることを確かめておく。
    // ここが 0 のまま始まると、何もしない実装でも最後の expect が通る
    expect(provider.activeFilterCount, 4);

    await pumpSheet(tester);
    await tapInSheet(tester, find.text('リセット'));

    expect(provider.filterCategoryIds, isEmpty);
    expect(provider.filterMemberIds, isEmpty);
    expect(provider.filterMinAmount, isNull);
    expect(provider.filterMaxAmount, isNull);
    expect(provider.filterMemoQuery, '');
    expect(provider.activeFilterCount, 0);
  });
}
