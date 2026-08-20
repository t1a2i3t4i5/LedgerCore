import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/transaction_filter_sheet.dart';
import 'package:ledger_app/screens/transactions_screen.dart';
import 'package:ledger_app/widgets/amount_format.dart';
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
    await db.insertTransaction(
      TransactionInput(
        memberId: members[memberIndex].id,
        categoryId: cats[categoryIndex].id,
        amount: amount,
        spentAt: DateTime(fixedNow.year, fixedNow.month, day),
        memo: memo,
      ),
    );
  }

  /// 実画面と同じく `showModalBottomSheet` で開く。
  ///
  /// シートを直接 `home` に置くと、`_apply` の `Navigator.pop()` が唯一のルートを
  /// 外してツリーが空になる。その状態では `find.text(...)` が何に対しても
  /// `findsNothing` になり、「エラーが出ていないこと」を見るアサーションが
  /// 無条件に通ってしまう（実際、成功パスに `_showError` を差し込んでも通った）。
  /// シートの下に画面を残しておけば、pop 後も SnackBar を検出できる。
  ///
  /// カテゴリとメンバーは既定で読み込み済みにしてから開く。生成しただけの
  /// Provider を渡すと「カテゴリがありません」だけが出て `FilterChip` が
  /// 1 つも描かれず、チップの経路を通せないため。
  ///
  /// [preloaded] を false にすると、実画面の `_openFilterSheet`
  /// （`transactions_screen.dart`。未読込なら fetch を投げるが **await せずに**
  /// シートを開く）と同じ順序になる。空のまま開いて、あとから届いた通知で
  /// チップが出る経路を通したいときに使う。
  Future<void> pumpSheet(WidgetTester tester, {bool preloaded = true}) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final categoryProvider = CategoryProvider(db);
    final memberProvider = MemberProvider(db);
    if (preloaded) {
      await categoryProvider.fetch();
      await memberProvider.fetchMembers();
    }

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
              builder:
                  (context) => ElevatedButton(
                    onPressed:
                        () => showModalBottomSheet<void>(
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

    if (!preloaded) {
      // 開いた時点ではまだ空。ここでチップが出ていると「あとから届く」
      // 経路を通せないので、前提として確かめておく
      expect(find.text('カテゴリがありません'), findsOneWidget);
      await categoryProvider.fetch();
      await memberProvider.fetchMembers();
      await tester.pumpAndSettle();
    }
  }

  /// 実画面（一覧 → フィルターボタン → シート）をそのまま組み立てる。
  ///
  /// [pumpSheet] はシートしか描かないので、適用の結果が Provider から一覧へ
  /// 伝わるところ（`setFilters` の `notifyListeners` と、一覧が
  /// `filteredTransactions` を読んでいること）は、そちらでは判定できない。
  /// Provider の getter は通知と無関係に正しい値を返すため。
  Future<void> pumpTransactionsScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider(create: (_) => MemberProvider(db)),
          ChangeNotifierProvider.value(value: provider),
        ],
        // TransactionsScreen は自前で Scaffold を返す
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
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
  Finder memoField() => find.widgetWithText(TextFormField, 'メモに含まれる文字列');

  /// フォーマッタの桁数制限を抜ける経路（IME の変換確定前）で [text] を送る。
  ///
  /// composing 中の値は素通しされる仕様なので、桁数制限を超えた文字列が
  /// そのままコントローラに載る。
  ///
  /// 欄にフォーカスを当てるのも [tapInSheet] 経由にする。素の `tap` だと
  /// 欄が可視域の外にあったときミスするが、それは警告止まりで例外にならない。
  /// composing が一度も送られないまま「適用」が押され、通るはずのない
  /// アサーションが理由の分からない形で落ちる（カテゴリを 10 件足すと再現する）。
  Future<void> sendComposing(
    WidgetTester tester,
    Finder field,
    String text,
  ) async {
    await tapInSheet(tester, field);

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange(start: 0, end: text.length),
      ),
    );
    await tester.pump();
  }

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
    await sendComposing(tester, minField(), '9' * 400);

    await tapInSheet(tester, find.text('適用'));

    expect(find.text('最小金額が不正な値です'), findsOneWidget);
    expect(provider.filterMinAmount, isNull);
  });

  // 最大側にも同じガードが要る。min だけ守られていると、max に Infinity が
  // 入って全件が除外され、開き直しても欄に 'Infinity' が復元されて再適用が
  // 効かず、リセットするまで戻らない（min 側と同じ事故が起きる）
  testWidgets('composing 中の桁あふれは最大金額側でも適用されない', (tester) async {
    await pumpSheet(tester);
    await sendComposing(tester, maxField(), '9' * 400);

    await tapInSheet(tester, find.text('適用'));

    expect(find.text('最大金額が不正な値です'), findsOneWidget);
    expect(provider.filterMaxAmount, isNull);
  });

  testWidgets('上限を超える値は適用されない', (tester) async {
    await pumpSheet(tester);

    // 桁数制限を抜ける経路（composing）で上限超過の有限値を送る
    await sendComposing(
      tester,
      minField(),
      (kMaxAmount + 1).toStringAsFixed(0),
    );

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
    // エラーのときは閉じない。閉じると打ち直しに開き直しが要る
    expect(find.byType(TransactionFilterSheet), findsOneWidget);
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
    // 状態だけでなく、一覧が読む filteredTransactions の順番まで見る。
    // ただしここで描いているのはシートだけなので、この並びが実際に画面へ
    // 反映されるかは別（「適用した絞り込みが一覧に反映される」で見る）
    expect(provider.filteredTransactions.map((t) => t.amount).toList(), [
      1000,
      3000,
    ]);
    // 適用したらシートは閉じる。閉じないと絞り込んだ一覧が見えない
    expect(find.byType(TransactionFilterSheet), findsNothing);
  });

  testWidgets('適用した絞り込みが一覧に反映される', (tester) async {
    // 既定カテゴリの 0 番目が食費、2 番目が交通費
    await seedTransaction(amount: 1200, categoryIndex: 0);
    await seedTransaction(amount: 3400, categoryIndex: 2);

    await pumpTransactionsScreen(tester);
    expect(find.text('2件'), findsOneWidget);
    expect(find.text('¥1,200'), findsOneWidget);

    await tester.tap(find.byTooltip('ソート・フィルター'));
    await tester.pumpAndSettle();
    await tapInSheet(tester, find.widgetWithText(FilterChip, '交通費'));
    await tapInSheet(tester, find.text('適用'));

    // Provider が通知し、一覧が filteredTransactions を読み直したか。
    // setFilters の notifyListeners を消すと、シートは閉じるのに
    // 一覧は 2 件のまま残る
    expect(find.text('1件'), findsOneWidget);
    expect(find.text('¥1,200'), findsNothing);
    expect(find.text('¥3,400'), findsOneWidget);
  });

  testWidgets('読み込みが終わる前に開いても、届いたチップで絞り込める', (tester) async {
    final cats = await db.getCategories();
    final target = cats.firstWhere((c) => c.name == '交通費');

    // 実画面はカテゴリの読み込みを待たずにシートを開く。シートが
    // context.watch をやめると、実機ではチップが出ないまま固定される
    await pumpSheet(tester, preloaded: false);

    await tapInSheet(tester, find.widgetWithText(FilterChip, '交通費'));
    await tapInSheet(tester, find.text('適用'));

    expect(provider.filterCategoryIds, {target.id});
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
    expect(find.byType(TransactionFilterSheet), findsNothing);
  });

  // ---- 復元 ----

  testWidgets('適用中の条件が全項目そろって復元される', (tester) async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertMember('配偶者');
    final spouse = (await db.getMembers()).firstWhere((m) => m.name == '配偶者');

    provider.setSort(TransactionSortField.amount, SortOrder.asc);
    provider.setFilters(
      categoryIds: {cats.firstWhere((c) => c.name == '交通費').id},
      memberIds: {spouse.id},
      minAmount: 1000,
      maxAmount: 5000,
      memoQuery: 'コンビニ',
    );

    await pumpSheet(tester);

    // 開いた時点で全項目が Provider 由来になっているか。
    // チップは selected、ソートは金額・昇順、メモ欄には文字列が入る
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '交通費'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '配偶者'))
          .selected,
      isTrue,
    );
    // 選んでいない側まで拾っていないことも見る
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '食費')).selected,
      isFalse,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.widgetWithText(FilterChip, members.first.name),
          )
          .selected,
      isFalse,
    );
    expect(find.byTooltip('昇順'), findsOneWidget);
    expect(find.text('コンビニ'), findsOneWidget);

    // 金額だけ打ち替えて適用しても、他の条件は消えずに往復する。
    // initState の復元が抜けると、ここで黙って 1 件だけに減る
    await tester.enterText(minField(), '2000');
    await tapInSheet(tester, find.text('適用'));

    expect(provider.filterMinAmount, 2000);
    expect(provider.filterMaxAmount, 5000);
    expect(provider.filterCategoryIds, {
      cats.firstWhere((c) => c.name == '交通費').id,
    });
    expect(provider.filterMemberIds, {spouse.id});
    expect(provider.filterMemoQuery, 'コンビニ');
    expect(provider.sortField, TransactionSortField.amount);
    expect(provider.sortOrder, SortOrder.asc);
  });
}
