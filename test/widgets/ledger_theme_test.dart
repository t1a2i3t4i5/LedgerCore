import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';

void main() {
  testWidgets('Card の解決後の背景は白になる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ledgerTheme,
        home: const Scaffold(
          body: Card(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(of: find.byType(Card), matching: find.byType(Material)),
    );
    expect(material.color, const Color(0xFFFFFFFF));
  });

  test('AppBar はスクロール時にも elevation を付けない', () {
    expect(ledgerTheme.appBarTheme.scrolledUnderElevation, 0);
  });

  test('中見出しは Zen Kaku Gothic New を使う', () {
    expect(ledgerTheme.textTheme.titleMedium?.fontFamily, 'ZenKakuGothicNew');
  });

  test('大きな金額は Outfit を使う', () {
    expect(LedgerTokens.amountLarge.fontFamily, 'Outfit');
  });
}
