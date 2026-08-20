import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/summary_screen.dart';
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:provider/provider.dart';

/// テキストが横幅に収まらず ellipsis で畳まれたかどうか。
///
/// `find.text()` は Text が持つ文字列を見るだけなので、実際に「…」へ潰れていても
/// マッチしてしまう。畳まれたかは描画側の RenderParagraph だけが知っている。
bool _isEllipsized(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

/// カテゴリ名の行に、その金額と構成比が**同じ `ListTile` の中に**出ていること。
///
/// 画面のどこかに '¥7,500' と '75.0%' があることを別々に見るだけでは、
/// 行と行で中身が入れ替わっても気付けない（集合としては一致するため）。
void expectRow(
  WidgetTester tester,
  String categoryName, {
  required String amount,
  required String ratio,
}) {
  final tile = find.ancestor(
    of: find.text(categoryName),
    matching: find.byType(ListTile),
  );
  expect(tile, findsOneWidget, reason: '$categoryName の行が無い');
  expect(
    find.descendant(of: tile, matching: find.text(amount)),
    findsOneWidget,
    reason: '$categoryName の行に $amount が無い',
  );
  expect(
    find.descendant(of: tile, matching: find.text(ratio)),
    findsOneWidget,
    reason: '$categoryName の行に $ratio が無い',
  );
}

/// 行の先頭の丸アイコンが、そのカテゴリ ID の [categoryColor] で塗られていること。
///
/// 円グラフが消えて chart_palette の lib 側の利用者はこの CircleAvatar だけに
/// なったので、ここを直書きの色に変えても落ちるテストが無い状態を避ける。
void expectAvatarColor(
  WidgetTester tester,
  String categoryName,
  int categoryId,
) {
  final avatar = tester.widget<CircleAvatar>(
    find.descendant(
      of: find.ancestor(
        of: find.text(categoryName),
        matching: find.byType(ListTile),
      ),
      matching: find.byType(CircleAvatar),
    ),
  );
  expect(avatar.backgroundColor, categoryColor(categoryId));

  final icon = tester.widget<Icon>(
    find.descendant(
      of: find.ancestor(
        of: find.text(categoryName),
        matching: find.byType(ListTile),
      ),
      matching: find.byType(Icon),
    ),
  );
  // 背景の輝度で白黒を選ぶ。直書きすると暗い色の上で読めなくなる
  expect(icon.color, labelColorOn(categoryColor(categoryId)));
}

/// サマリー画面のカテゴリ別セクションを、インメモリ DB 込みで確認する。
/// 実端末のファイルには触らない（database_test.dart と同じ方針）。
void main() {
  late AppDatabase db;

  // 画面が表示する月を実時刻から切り離す（seed と表示で月がずれないように）
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpSummary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
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

  // 行数だけを数えると、行と行で中身が入れ替わる改変を検知できない
  // （カテゴリ 3 + メンバー 1 = 4 件は保たれるため）。名前・金額・構成比が
  // 同じ ListTile に収まっているかまで見る
  testWidgets('カテゴリごとに名前・金額・構成比が同じ行に並ぶ', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;

    // 合計 6000 円。構成比が割り切れて重複しない配分にする
    for (final (i, cat) in cats.take(3).indexed) {
      await db.insertTransaction(TransactionInput(
        memberId: memberId,
        categoryId: cat.id,
        amount: (i + 1) * 1000,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ));
    }

    await pumpSummary(tester);

    expect(tester.takeException(), isNull);
    expectRow(tester, cats[2].name, amount: '¥3,000', ratio: '50.0%');
    expectRow(tester, cats[1].name, amount: '¥2,000', ratio: '33.3%');
    expectRow(tester, cats[0].name, amount: '¥1,000', ratio: '16.7%');
    expect(find.text('データがありません'), findsNothing);
  });

  // 金額の降順（summary_calculator の _buildCategoryItems）。この並びが崩れると
  // 「支出の大きい順に見る」という画面の前提が静かに壊れる
  testWidgets('カテゴリ別は金額の降順で並ぶ', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;

    for (final (i, cat) in cats.take(3).indexed) {
      await db.insertTransaction(TransactionInput(
        memberId: memberId,
        categoryId: cat.id,
        amount: (i + 1) * 1000,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ));
    }

    await pumpSummary(tester);

    double dy(String name) => tester.getCenter(find.text(name)).dy;
    expect(dy(cats[2].name), lessThan(dy(cats[1].name)));
    expect(dy(cats[1].name), lessThan(dy(cats[0].name)));
  });

  // chart_palette の lib 側の利用者は、円グラフが消えてこの CircleAvatar だけに
  // なった。色を直書きに変えても落ちるテストが無い状態を避ける
  testWidgets('行の丸アイコンはカテゴリの色で塗られる', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;

    for (final (i, cat) in cats.take(2).indexed) {
      await db.insertTransaction(TransactionInput(
        memberId: memberId,
        categoryId: cat.id,
        amount: (i + 1) * 1000,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ));
    }

    await pumpSummary(tester);

    expectAvatarColor(tester, cats[0].name, cats[0].id);
    expectAvatarColor(tester, cats[1].name, cats[1].id);
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
    expect(find.text('合計支出'), findsOneWidget);
    expect(find.text('¥0'), findsOneWidget);
    expect(find.text('カテゴリ別'), findsOneWidget);
    expect(find.text('メンバー別'), findsOneWidget);
    // 行そのものは 1 つも無い
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
      await db.insertTransaction(TransactionInput(
        memberId: memberId,
        categoryId: cats.firstWhere((c) => c.name == categoryName).id,
        amount: amount,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ));
    }

    testWidgets('金額の下に構成比が並ぶ', (tester) async {
      await seed('食費', 7500);
      await seed('日用品', 2500);

      await pumpSummary(tester);

      // 金額と % は別の Text。1 行に連結すると title の幅が足りなくなる。
      // どちらの行に出ているかまで見る（集合として一致するだけでは足りない）
      expectRow(tester, '食費', amount: '¥7,500', ratio: '75.0%');
      expectRow(tester, '日用品', amount: '¥2,500', ratio: '25.0%');
    });

    // trailing を縦積みにした理由そのもの。金額と % を 1 行に連結していた
    // 時点では、実測で title の取り分が 43.5px しか残らず全角 4 文字で畳まれた
    // （縦積みなら 135.5px）。既定カテゴリは 2〜3 文字でどちらでも収まって
    // しまうので、ユーザーが実際に作る長さの名前で見る。
    //
    // ListTile は overflow を例外にせず静かに畳み、find.text() は畳まれた
    // Text にもマッチするので、省略の有無は RenderParagraph に訊く
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

    // 縦積みで行が高くならないことの固定。dense の最小高 48px に 2 行が
    // 収まっているので、金額だけだった頃と行の見え方は変わらない
    testWidgets('構成比を足しても行の高さは dense のまま', (tester) async {
      await seed('食費', 50000);

      await pumpSummary(tester);

      final tile = find.ancestor(
        of: find.text('食費'),
        matching: find.byType(ListTile),
      );
      expect(tester.getSize(tile).height, 48.0);
    });

    // #45 の動機そのもの。かつてのドーナツグラフは _minLabelRatio = 0.05 未満の
    // 扇形にラベルを出さず、細かいカテゴリの割合はどこにも出ていなかった。
    // リストは件数によらず全カテゴリに出す
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
      // 畳まれても行が伸びない（ListTile が高さを吸収している）
      final tile = find.ancestor(
        of: find.text('あ' * 50),
        matching: find.byType(ListTile),
      );
      expect(tester.getSize(tile).height, 48.0);
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
}
