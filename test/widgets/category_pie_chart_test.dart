import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/models/summary.dart';
import 'package:ledger_app/widgets/category_pie_chart.dart';

/// 扇形の上に描かれる % ラベルは fl_chart が Canvas に直接描くため
/// find.text() では拾えない。検証対象は凡例側のテキストに限る。
/// 凡例は「カテゴリ名 ¥金額」を 1 つの Text にまとめているので
/// カテゴリ名の検証には find.textContaining() を使う。
Future<void> _pump(
  WidgetTester tester,
  List<CategorySummaryItem> items, {
  // 既定のテスト画面(800x600)は実機より広く overflow を見逃すので、
  // 一般的なスマホ幅で描画する
  Size surfaceSize = const Size(360, 690),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [CategoryPieChart(items: items)],
        ),
      ),
    ),
  );
  // PieChart は postFrameCallback と暗黙アニメーションを持つので落ち着かせる
  await tester.pumpAndSettle();
}

CategorySummaryItem _item(int id, String name, double total) =>
    CategorySummaryItem(categoryId: id, categoryName: name, total: total);

/// 描画された PieChart のセクション定義を取り出す。
/// 扇形は Canvas 直描きなので、中身の検証はこのデータに対して行う。
List<PieChartSectionData> _sections(WidgetTester tester) =>
    tester.widget<PieChart>(find.byType(PieChart)).data.sections;

void main() {
  group('CategoryPieChart', () {
    testWidgets('空リストのときは「データがありません」を出しグラフを描かない',
        (tester) async {
      await _pump(tester, const []);

      expect(find.text('データがありません'), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
    });

    testWidgets('合計が0のときもグラフを描かない', (tester) async {
      await _pump(tester, [_item(1, '食費', 0)]);

      expect(find.text('データがありません'), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
    });

    testWidgets('項目が渡されたとき凡例にカテゴリ名が出る', (tester) async {
      await _pump(tester, [
        _item(1, '食費', 1500),
        _item(2, '交通費', 500),
      ]);

      expect(find.byType(PieChart), findsOneWidget);
      expect(find.textContaining('食費'), findsOneWidget);
      expect(find.textContaining('交通費'), findsOneWidget);
      expect(find.text('データがありません'), findsNothing);
    });

    testWidgets('カテゴリ1件でも例外なく描画される', (tester) async {
      await _pump(tester, [_item(3, '日用品', 800)]);

      expect(tester.takeException(), isNull);
      expect(find.byType(PieChart), findsOneWidget);
      expect(find.textContaining('日用品'), findsOneWidget);
    });

    testWidgets('既定カテゴリ相当の10件でもスマホ幅でレイアウトが崩れない',
        (tester) async {
      final items = List.generate(
        10,
        (i) => _item(i + 1, 'カテゴリ${i + 1}', (10 - i) * 100),
      );

      await _pump(tester, items);

      // overflow が起きると RenderFlex の例外が上がる
      expect(tester.takeException(), isNull);
      expect(find.byType(PieChart), findsOneWidget);
      expect(find.textContaining('カテゴリ10'), findsOneWidget);
    });

    // カテゴリ名はユーザーが編集でき、DB は 50 文字まで許可している
    // （categories_screen.dart の TextField に maxLength は無い）。
    // Flexible で包む前は 25 文字で凡例が横にはみ出していた。
    for (final length in [25, 50]) {
      testWidgets('カテゴリ名が$length文字でも凡例がはみ出さない', (tester) async {
        await _pump(tester, [
          _item(1, 'あ' * length, 6000),
          _item(2, '食費', 4000),
        ]);

        expect(tester.takeException(), isNull);
        expect(find.byType(PieChart), findsOneWidget);
      });
    }
  });

  group('CategoryPieChart のセクション', () {
    testWidgets('金額と並び順が入力どおりセクションに渡る', (tester) async {
      await _pump(tester, [
        _item(1, '食費', 6000),
        _item(2, '交通費', 3000),
        _item(3, '日用品', 1000),
      ]);

      final sections = _sections(tester);
      expect(sections.map((s) => s.value), [6000, 3000, 1000]);
    });

    testWidgets('構成比を小数1桁のラベルにする', (tester) async {
      await _pump(tester, [
        _item(1, '食費', 7500),
        _item(2, '交通費', 2500),
      ]);

      final sections = _sections(tester);
      expect(sections[0].title, '75.0%');
      expect(sections[1].title, '25.0%');
      expect(sections.every((s) => s.showTitle), isTrue);
    });

    testWidgets('構成比5%未満のセクションはラベルを出さない', (tester) async {
      // 96% / 4% にして、境界の下側だけラベルが消えることを見る
      await _pump(tester, [
        _item(1, '食費', 9600),
        _item(2, '交通費', 400),
      ]);

      final sections = _sections(tester);
      expect(sections[0].showTitle, isTrue);
      expect(sections[1].showTitle, isFalse);
      // 非表示でも凡例には出るので情報は落ちない
      expect(find.textContaining('交通費'), findsOneWidget);
    });

    testWidgets('ちょうど5%のセクションはラベルを出す', (tester) async {
      await _pump(tester, [
        _item(1, '食費', 9500),
        _item(2, '交通費', 500),
      ]);

      expect(_sections(tester)[1].showTitle, isTrue);
    });
  });
}
