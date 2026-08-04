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
  });
}
