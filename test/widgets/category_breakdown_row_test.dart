import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/widgets/category_breakdown_row.dart';

Future<void> _pumpRow(
  WidgetTester tester, {
  required double textScale,
  double amount = 100,
  double total = 100,
  String categoryName = '食費（外食）',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ledgerTheme,
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SizedBox(
              width: 328,
              child: CategoryBreakdownRow(
                categoryName: categoryName,
                amount: amount,
                total: total,
                color: const Color(0xFF3D7F78),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('文字倍率2.0でも構成比の末尾まで収まる', (tester) async {
    await _pumpRow(tester, textScale: 2);

    final paragraph = tester.renderObject<RenderParagraph>(find.text('100.0%'));
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(paragraph.size.width + 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字倍率に応じて文字と行の高さが伸びる', (tester) async {
    await _pumpRow(tester, textScale: 1);
    final normalTextHeight = tester.getSize(find.text('食費（外食）')).height;
    final normalRowHeight =
        tester.getSize(find.byType(CategoryBreakdownRow)).height;

    await _pumpRow(tester, textScale: 2);
    final largeTextHeight = tester.getSize(find.text('食費（外食）')).height;
    final largeRowHeight =
        tester.getSize(find.byType(CategoryBreakdownRow)).height;

    expect(normalRowHeight, 64);
    expect(largeTextHeight, greaterThan(normalTextHeight * 1.8));
    expect(largeRowHeight, greaterThan(normalRowHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字倍率2.0と上限額でも横方向に溢れない', (tester) async {
    await _pumpRow(tester, textScale: 2, amount: kMaxAmount, total: kMaxAmount);

    expect(find.text('¥999,999,999,999'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
