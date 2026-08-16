import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/summary_screen.dart';
import 'package:provider/provider.dart';

/// テキストが横幅に収まらず ellipsis で畳まれたかどうか。
///
/// `find.text()` は Text が持つ文字列を見るだけなので、実際に「…」へ潰れていても
/// マッチしてしまう。畳まれたかは描画側の RenderParagraph だけが知っている。
bool _isEllipsized(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

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

  testWidgets('取引があるとカテゴリ別に行が並ぶ', (tester) async {
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

    expect(tester.takeException(), isNull);
    // カテゴリ 3 件 + メンバー 1 件
    expect(find.byType(ListTile), findsNWidgets(4));
    expect(find.text('データがありません'), findsNothing);
  });

  // 取引ゼロの月でも summary は非 null で返る（byCategory が空、total が 0）ため、
  // 画面の summary == null 分岐では受からない。この文言はドーナツグラフを外す
  // まで CategoryPieChart 側が出していたもので、受け皿を画面へ移してある。
  // summary_screen.dart の byCategory.isEmpty 分岐を消すとここが落ちる
  testWidgets('取引ゼロの月はカテゴリ別に「データがありません」が出る',
      (tester) async {
    await pumpSummary(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('データがありません'), findsOneWidget);
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

      // 金額と % は別の Text。1 行に連結すると title の幅が足りなくなる
      expect(find.text('¥7,500'), findsOneWidget);
      expect(find.text('75.0%'), findsOneWidget);
      expect(find.text('¥2,500'), findsOneWidget);
      expect(find.text('25.0%'), findsOneWidget);
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

      expect(find.text('2.0%'), findsOneWidget);
    });

    // 上限額 + DB が許す最大長のカテゴリ名。金額を描くテストには kMaxAmount の
    // ケースを置く（docs/testing.md）
    testWidgets('上限額と50文字のカテゴリ名でもレイアウトが崩れない',
        (tester) async {
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
