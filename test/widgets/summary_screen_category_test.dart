import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/category.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/summary_screen.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/category_breakdown_row.dart';
import 'package:ledger_app/widgets/category_breakdown_sheet.dart';
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:ledger_app/widgets/ledger_card.dart';
import 'package:ledger_app/widgets/ratio_bar.dart';
import 'package:provider/provider.dart';
import '../seed.dart';

/// テキストが横幅に収まらず ellipsis で畳まれたかどうか。
///
/// `find.text()` は Text が持つ文字列を見るだけなので、実際に「…」へ潰れていても
/// マッチしてしまう。畳まれたかは描画側の RenderParagraph だけが知っている。
bool _isEllipsized(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

/// カテゴリ名の行に、その金額と構成比が同じ公開ウィジェット内に出ていること。
///
/// 画面のどこかに '¥7,500' と '75.0%' があることを別々に見るだけでは、
/// 行と行で中身が入れ替わっても気付けない（集合としては一致するため）。
void expectRow(
  WidgetTester tester,
  String categoryName, {
  required String amount,
  required String ratio,
}) {
  final row = find.ancestor(
    of: find.text(categoryName),
    matching: find.byType(CategoryBreakdownRow),
  );
  expect(row, findsOneWidget, reason: '$categoryName の行が無い');
  expect(
    find.descendant(of: row, matching: find.text(amount)),
    findsOneWidget,
    reason: '$categoryName の行に $amount が無い',
  );
  expect(
    find.descendant(of: row, matching: find.text(ratio)),
    findsOneWidget,
    reason: '$categoryName の行に $ratio が無い',
  );
}

/// 行の色ドットと帯が、そのカテゴリ ID の [categoryColor] で描かれること。
void expectCategoryVisuals(
  WidgetTester tester,
  String categoryName,
  int categoryId,
  int? colorValue,
) {
  final row = find.ancestor(
    of: find.text(categoryName),
    matching: find.byType(CategoryBreakdownRow),
  );
  final expectedColor = categoryColor(categoryId, colorValue: colorValue);

  final dot = tester.widget<CircleAvatar>(
    find.descendant(of: row, matching: find.byType(CircleAvatar)),
  );
  expect(dot.backgroundColor, expectedColor);

  expect(
    find.descendant(of: row, matching: find.byType(RatioBar)),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == expectedColor,
      ),
    ),
    findsOneWidget,
  );
}

/// サマリー画面のカテゴリ別セクションを、インメモリ DB 込みで確認する。
/// 実端末のファイルには触らない（database_test.dart と同じ方針）。
void main() {
  late AppDatabase db;

  // 画面が表示する月を実時刻から切り離す（seed と表示で月がずれないように）
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // onCreate はメンバーを投入しないので、テスト側で用意する（#144）
    await seedMembers(db);
  });
  tearDown(() async => db.close());

  Future<void> pumpSummary(
    WidgetTester tester, {
    Size size = const Size(360, 690),
  }) async {
    tester.view.physicalSize = size;
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

  /// 保存順の先頭から、指定した金額でカテゴリごとに取引を 1 件積む。
  Future<List<CategoryView>> seedCategoryTotals(List<double> amounts) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;
    for (final (index, amount) in amounts.indexed) {
      await db.insertTransaction(
        TransactionInput(
          memberId: memberId,
          categoryId: cats[index].id,
          amount: amount,
          spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
        ),
      );
    }
    return cats;
  }

  // 行数だけを数えると、行と行で中身が入れ替わる改変を検知できない
  // （カテゴリ 3 + メンバー 1 = 4 件は保たれるため）。名前・金額・構成比が
  // 同じ CategoryBreakdownRow に収まっているかまで見る
  testWidgets('カテゴリごとに名前・金額・構成比が同じ行に並ぶ', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;

    // 合計 6000 円。構成比が割り切れて重複しない配分にする
    for (final (i, cat) in cats.take(3).indexed) {
      await db.insertTransaction(
        TransactionInput(
          memberId: memberId,
          categoryId: cat.id,
          amount: (i + 1) * 1000,
          spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
        ),
      );
    }

    await pumpSummary(tester);

    expect(tester.takeException(), isNull);
    expectRow(tester, cats[2].name, amount: '¥3,000', ratio: '50.0%');
    expectRow(tester, cats[1].name, amount: '¥2,000', ratio: '33.3%');
    expectRow(tester, cats[0].name, amount: '¥1,000', ratio: '16.7%');
    expect(find.text('データがありません'), findsNothing);
  });

  testWidgets('メンバー別アバターは保存色と絵文字の頭文字を使う', (tester) async {
    final memberId = (await db.getMembers()).single.id;
    final selectedColor = memberPalette.last;
    await db.updateMemberName(memberId, '🌸はな');
    await db.updateMemberColor(memberId, selectedColor.toARGB32());
    final member = (await db.getMembers()).single;
    await db.insertTransaction(
      TransactionInput(
        memberId: member.id,
        categoryId: (await db.getCategories()).first.id,
        amount: 1000,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ),
    );

    await pumpSummary(tester);

    expect(tester.takeException(), isNull);
    final row = find.ancestor(
      of: find.text(member.name),
      matching: find.byType(ListTile),
    );
    final avatarFinder = find.descendant(
      of: row,
      matching: find.byType(CircleAvatar),
    );
    final avatar = tester.widget<CircleAvatar>(avatarFinder);
    expect(avatar.backgroundColor, selectedColor);
    expect(
      find.descendant(of: avatarFinder, matching: find.text('🌸')),
      findsOne,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: avatarFinder, matching: find.text('🌸')),
          )
          .style
          ?.color,
      labelColorOn(selectedColor),
    );
  });

  testWidgets('カテゴリ別は金額降順で、同額なら保存順に並ぶ', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;

    for (final (i, amount) in [2000.0, 2000.0, 3000.0].indexed) {
      await db.insertTransaction(
        TransactionInput(
          memberId: memberId,
          categoryId: cats[i].id,
          amount: amount,
          spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
        ),
      );
    }

    await pumpSummary(tester);

    double dy(String name) => tester.getCenter(find.text(name)).dy;
    expect(dy(cats[2].name), lessThan(dy(cats[0].name)));
    expect(dy(cats[0].name), lessThan(dy(cats[1].name)));
  });

  group('カテゴリ別の上位表示と全件シート', () {
    testWidgets('ホームは上位4件だけを表示し、5件で「もっとみる」を出す', (tester) async {
      final cats = await seedCategoryTotals([2000, 6000, 1000, 5000, 3000]);
      final expected = [cats[1], cats[3], cats[4], cats[0], cats[2]];

      await pumpSummary(tester);

      expect(find.byType(CategoryBreakdownRow), findsNWidgets(4));
      for (final cat in expected.take(4)) {
        expect(find.text(cat.name), findsOneWidget);
      }
      for (final cat in expected.skip(4)) {
        expect(find.text(cat.name), findsNothing);
      }
      expect(find.text('もっとみる'), findsOneWidget);
    });

    testWidgets('4件以下では「もっとみる」を出さない', (tester) async {
      await seedCategoryTotals([4000, 3000, 2000, 1000]);

      await pumpSummary(tester);

      expect(find.byType(CategoryBreakdownRow), findsNWidgets(4));
      expect(find.text('もっとみる'), findsNothing);
    });

    testWidgets('シートは同じ並びの全件を月合計の構成比で表示する', (tester) async {
      final cats = await seedCategoryTotals([
        2000,
        6000,
        1000,
        5000,
        3000,
        4000,
      ]);
      final expected = [cats[1], cats[3], cats[5], cats[4], cats[0], cats[2]];

      await pumpSummary(tester);
      await tester.ensureVisible(find.text('もっとみる'));
      await tester.tap(find.text('もっとみる'));
      await tester.pumpAndSettle();

      final sheet = find.byType(CategoryBreakdownSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('2026年7月のカテゴリ別')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(CategoryBreakdownRow)),
        findsNWidgets(6),
      );

      double sheetDy(String name) =>
          tester
              .getCenter(find.descendant(of: sheet, matching: find.text(name)))
              .dy;
      for (var i = 0; i < 5; i++) {
        expect(
          sheetDy(expected[i].name),
          lessThan(sheetDy(expected[i + 1].name)),
        );
      }

      final lastRow = find.descendant(
        of: sheet,
        matching: find.ancestor(
          of: find.text(expected.last.name),
          matching: find.byType(CategoryBreakdownRow),
        ),
      );
      expect(
        find.descendant(of: lastRow, matching: find.text('¥1,000')),
        findsOneWidget,
      );
      // 1,000 / 21,000。上位4件の小計ではなく月合計が分母になる。
      expect(
        find.descendant(of: lastRow, matching: find.text('4.8%')),
        findsOneWidget,
      );
    });

    testWidgets('件数が多いシートは画面より低く、一覧内で末尾までスクロールできる', (tester) async {
      final cats = await seedCategoryTotals([
        10000,
        9000,
        8000,
        7000,
        6000,
        5000,
        4000,
        3000,
        2000,
        1000,
      ]);

      tester.view.padding = const FakeViewPadding(bottom: 34);
      await pumpSummary(tester, size: const Size(390, 844));
      await tester.ensureVisible(find.text('もっとみる'));
      await tester.tap(find.text('もっとみる'));
      await tester.pumpAndSettle();

      final sheet = find.byType(CategoryBreakdownSheet);
      final bottomSheet = find.byType(BottomSheet);
      expect(tester.getSize(bottomSheet).height, lessThanOrEqualTo(844 * 0.8));

      final sheetScrollable = find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.descendant(of: sheet, matching: find.text(cats.last.name)),
        200,
        scrollable: sheetScrollable,
      );
      expect(
        find.descendant(of: sheet, matching: find.text(cats.last.name)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('広い画面でも全件シートは480pxで中央に置かれる', (tester) async {
      await seedCategoryTotals([6000, 5000, 4000, 3000, 2000]);

      await pumpSummary(tester, size: const Size(788, 690));
      await tester.ensureVisible(find.text('もっとみる'));
      await tester.tap(find.text('もっとみる'));
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byType(CategoryBreakdownSheet));
      expect(rect.width, 480);
      expect(rect.center.dx, closeTo(394, 0.01));
    });
  });

  // categoryColor は色ドットと帯に届く入口。画面側で直書きの色へ
  // 置き換えても落ちるテストが無い状態を避ける
  testWidgets('カテゴリ行は categoryColor でドットと帯を描く', (tester) async {
    var cats = await db.getCategories();
    await db.updateCategory(
      cats.first.id,
      cats.first.name,
      categoryPalette.last.toARGB32(),
    );
    cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;

    for (final (i, cat) in cats.take(2).indexed) {
      await db.insertTransaction(
        TransactionInput(
          memberId: memberId,
          categoryId: cat.id,
          amount: (i + 1) * 1000,
          spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
        ),
      );
    }

    await pumpSummary(tester);

    expectCategoryVisuals(tester, cats[0].name, cats[0].id, cats[0].colorValue);
    expectCategoryVisuals(tester, cats[1].name, cats[1].id, cats[1].colorValue);
  });

  // 取引ゼロの月でも summary は非 null で返る（byCategory が空、total が 0）ため、
  // 画面の summary == null 分岐では受からない。この文言はドーナツグラフを外す
  // まで CategoryPieChart 側が出していたもので、受け皿を画面へ移してある。
  // summary_screen.dart の byCategory.isEmpty 分岐を消すとここが落ちる
  //
  // 文言が 1 個あることだけを見ると、summary ごと null になる実装に変わっても
  // 緑のまま通る（その場合は合計カードも見出しも消える）。カテゴリ別の中だけが
  // 空で、画面の骨格は残っていることまで見る
  testWidgets('取引ゼロの月はどの見出しの下も「データがありません」になる', (tester) async {
    await pumpSummary(tester);

    expect(tester.takeException(), isNull);
    // 骨格は残る。summary == null 分岐に落ちるとこれらが消える
    expect(find.text('今月の支出'), findsOneWidget);
    expect(find.text('¥0'), findsOneWidget);
    expect(find.text('カテゴリ別'), findsOneWidget);
    expect(find.text('メンバー別'), findsOneWidget);
    // 行そのものは 1 つも無い
    expect(find.byType(CategoryBreakdownRow), findsNothing);
    expect(find.byType(ListTile), findsNothing);

    // **見出しを出したら、その下に必ず何かを描く。**
    // 取引ゼロの月は byCategory も byMember も空になる。かつてメンバー別には
    // 受け皿が無く、見出しの下が無言の空白になっていた
    final empties = find.text('データがありません');
    expect(empties, findsNWidgets(2));
    expect(
      tester.getRect(empties.at(0)).top,
      greaterThan(tester.getRect(find.text('カテゴリ別')).bottom),
      reason: 'カテゴリ別の見出しの下に受け皿が無い',
    );
    expect(
      tester.getRect(empties.at(1)).top,
      greaterThan(tester.getRect(find.text('メンバー別')).bottom),
      reason: 'メンバー別の見出しの下に受け皿が無い',
    );
  });

  group('カテゴリ別リストの構成比', () {
    /// カテゴリ名を指定して当月に 1 件積む。
    /// 既定カテゴリの並び順に依存させないよう、名前で引いて id を取る
    Future<void> seed(String categoryName, double amount) async {
      final cats = await db.getCategories();
      final memberId = (await db.getMembers()).first.id;
      await db.insertTransaction(
        TransactionInput(
          memberId: memberId,
          categoryId: cats.firstWhere((c) => c.name == categoryName).id,
          amount: amount,
          spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
        ),
      );
    }

    testWidgets('金額の右に構成比が並ぶ', (tester) async {
      await seed('食費', 7500);
      await seed('日用品', 2500);

      await pumpSummary(tester);

      // 金額と % は別の Text。どちらの行に出ているかまで見る。
      expectRow(tester, '食費', amount: '¥7,500', ratio: '75.0%');
      expectRow(tester, '日用品', amount: '¥2,500', ratio: '25.0%');
    });

    // trailing を縦積みにした理由そのもの。金額と % を 1 行に連結していた
    // 時点では、実測で title の取り分が 43.5px しか残らず全角 4 文字で畳まれた
    // （縦積みなら 135.5px）。既定カテゴリは 2〜3 文字でどちらでも収まって
    // しまうので、ユーザーが実際に作る長さの名前で見る。
    //
    // Expanded 内の Text は overflow を例外にせず静かに畳み、find.text() は
    // 畳まれた Text にもマッチするので、省略の有無は RenderParagraph に訊く
    testWidgets('現実的な金額と長さのカテゴリ名が省略されない', (tester) async {
      await db.insertCategory('食費（外食）'); // 6 文字
      await db.insertCategory('子供の習い事'); // 6 文字
      // 家計簿として普通の 5 桁。1 行連結だとこの組み合わせで畳まれていた
      await seed('食費（外食）', 50000);
      await seed('子供の習い事', 30000);

      await pumpSummary(tester);

      expect(_isEllipsized(tester, '食費（外食）'), isFalse);
      expect(_isEllipsized(tester, '子供の習い事'), isFalse);
    });

    testWidgets('通常倍率のカテゴリ行は2段でも基準高から伸びない', (tester) async {
      await seed('食費', 50000);

      await pumpSummary(tester);

      final row = find.ancestor(
        of: find.text('食費'),
        matching: find.byType(CategoryBreakdownRow),
      );
      expect(tester.getSize(row).height, 64);
    });

    // #45 の動機そのもの。かつてのドーナツグラフは _minLabelRatio = 0.05 未満の
    // 扇形にラベルを出さず、細かいカテゴリの割合はどこにも出ていなかった。
    // 全件シートでは小さいカテゴリも省かずに出す
    testWidgets('5%未満のカテゴリでも構成比が出る', (tester) async {
      await seed('食費', 9800);
      await seed('日用品', 200); // 2%

      await pumpSummary(tester);

      expectRow(tester, '日用品', amount: '¥200', ratio: '2.0%');
    });

    // 上限額 + DB が許す最大長のカテゴリ名。金額を描くテストには kMaxAmount の
    // ケースを置く（docs/testing.md）
    testWidgets('上限額と50文字のカテゴリ名でもレイアウトが崩れない', (tester) async {
      await db.insertCategory('あ' * 50);
      await seed('あ' * 50, kMaxAmount);

      await pumpSummary(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('¥999,999,999,999'), findsWidgets);
      expect(find.text('100.0%'), findsOneWidget);
      // 50 文字は畳まれて当然。ここが false になるようなら
      // _isEllipsized が省略を検知できておらず、上のケースも無意味になる
      expect(_isEllipsized(tester, 'あ' * 50), isTrue);
      // 通常倍率では、畳まれても公開定数で決めた基準高から伸びない
      final row = find.ancestor(
        of: find.text('あ' * 50),
        matching: find.byType(CategoryBreakdownRow),
      );
      expect(tester.getSize(row).height, 64);
    });

    // 変更範囲を広げていないことの固定。メンバー別は金額だけのまま
    testWidgets('メンバー別の行には構成比を出さない', (tester) async {
      await seed('食費', 7500);
      await seed('日用品', 2500);

      await pumpSummary(tester);

      // 自分 1 人なので、メンバー別はこの 1 行だけ
      final memberTile = find.ancestor(
        of: find.text('自分'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: memberTile, matching: find.text('¥10,000')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: memberTile, matching: find.textContaining('%')),
        findsNothing,
      );
    });
  });

  testWidgets('金額の字は構成比より大きい', (tester) async {
    final cat = (await db.getCategories()).first;
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: cat.id,
        amount: 1000,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ),
    );

    await pumpSummary(tester);

    final row = find.byType(CategoryBreakdownRow);
    final amount = tester.widget<Text>(
      find.descendant(of: row, matching: find.text('¥1,000')),
    );
    final ratio = tester.widget<Text>(
      find.descendant(of: row, matching: find.text('100.0%')),
    );
    expect(amount.style?.fontSize, greaterThan(ratio.style!.fontSize!));
  });

  testWidgets('合計カードは amountLarge と scaleDown を使う', (tester) async {
    await pumpSummary(tester);

    final amount = tester.widget<Text>(find.text('¥0'));
    expect(find.byType(LedgerCard), findsOneWidget);
    expect(amount.style?.fontFamily, LedgerTokens.amountLarge.fontFamily);
    expect(amount.style?.fontSize, LedgerTokens.amountLarge.fontSize);
    final fitted = find.ancestor(
      of: find.text('¥0'),
      matching: find.byType(FittedBox),
    );
    expect(fitted, findsOneWidget);
    expect(tester.widget<FittedBox>(fitted).fit, BoxFit.scaleDown);
  });

  testWidgets('広い画面でも本文幅は480pxで中央に置かれる', (tester) async {
    final cat = (await db.getCategories()).first;
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: cat.id,
        amount: 1000,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ),
    );

    await pumpSummary(tester, size: const Size(788, 690));

    final row = find.byType(CategoryBreakdownRow);
    final rect = tester.getRect(row);
    expect(rect.width, 480);
    expect(rect.center.dx, closeTo(394, 0.01));
    expect(find.byType(LayoutBuilder), findsWidgets);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.padding,
      const EdgeInsets.symmetric(horizontal: 154, vertical: 16),
    );
  });
}
