import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/ratio_bar.dart';

const _fillColor = Color(0xFF3D7F78);

Finder _coloredBox(Color color) => find.byWidgetPredicate(
  (widget) => widget is ColoredBox && widget.color == color,
);

Future<void> _pumpBar(
  WidgetTester tester, {
  required double amount,
  required double total,
  double width = 200,
  double height = 8,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: RatioBar(
              amount: amount,
              total: total,
              color: _fillColor,
              height: height,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('25% のとき塗り幅がトラック幅の 1/4 になる', (tester) async {
    await _pumpBar(tester, amount: 25, total: 100);

    final track = tester.getRect(_coloredBox(LedgerTokens.barTrack));
    final fill = tester.getRect(_coloredBox(_fillColor));
    expect(fill.width, closeTo(track.width / 4, 0.01));
  });

  testWidgets('金額が合計を超えても塗り幅がトラックを超えない', (tester) async {
    await _pumpBar(tester, amount: 150, total: 100);

    final track = tester.getRect(_coloredBox(LedgerTokens.barTrack));
    final fill = tester.getRect(_coloredBox(_fillColor));
    expect(fill.width, lessThanOrEqualTo(track.width));
    expect(fill.right, lessThanOrEqualTo(track.right));
  });

  testWidgets('0.3% でも塗り幅が 2px 以上ある', (tester) async {
    await _pumpBar(tester, amount: 0.3, total: 100);

    final fill = tester.getRect(_coloredBox(_fillColor));
    expect(fill.width, greaterThanOrEqualTo(2));
  });

  testWidgets('合計が 0 のとき例外を出さず塗り幅が 0 になる', (tester) async {
    await _pumpBar(tester, amount: 10, total: 0);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_coloredBox(_fillColor)).width, 0);
  });

  testWidgets('高さが引数どおり固定される', (tester) async {
    await _pumpBar(tester, amount: 25, total: 100, height: 13);

    expect(tester.getSize(find.byType(RatioBar)).height, 13);
    expect(tester.getRect(_coloredBox(LedgerTokens.barTrack)).height, 13);
  });
}
