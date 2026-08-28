import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/month_selector.dart';

void main() {
  Future<void> pumpSelector(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ledgerTheme,
        home: Scaffold(
          body: MonthSelector(
            year: 2026,
            month: 7,
            onPrev: () {},
            onNext: () {},
            onToday: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('月セレクタは二段見出しと 38px の角丸ボタンを描く', (tester) async {
    await pumpSelector(tester);

    final month = tester.widget<Text>(find.text('7月'));
    final year = tester.widget<Text>(find.text('2026'));
    expect(month.style?.fontSize, 38);
    expect(year.style?.fontFamily, LedgerTokens.periodYear.fontFamily);
    expect(year.style?.fontSize, 16);
    expect(find.text('今月'), findsOneWidget);

    final previousButton = find.ancestor(
      of: find.byIcon(Icons.chevron_left),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(previousButton), const Size.square(38));
    final shape = tester
        .widget<IconButton>(previousButton)
        .style
        ?.shape
        ?.resolve(<WidgetState>{});
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(14),
    );
  });

  test('期間セグメントは白い選択面と onSurface の文字を使う', () {
    final style = ledgerTheme.segmentedButtonTheme.style!;
    final selected = {WidgetState.selected};
    final background = style.backgroundColor!.resolve(selected)!;
    final foreground = style.foregroundColor!.resolve(selected)!;

    expect(background, ledgerTheme.colorScheme.surfaceContainerLowest);
    expect(foreground, ledgerTheme.colorScheme.onSurface);
    expect(style.shape!.resolve(selected), isA<StadiumBorder>());

    final lighter = [
      foreground.computeLuminance(),
      background.computeLuminance(),
    ].reduce((a, b) => a > b ? a : b);
    final darker = [
      foreground.computeLuminance(),
      background.computeLuminance(),
    ].reduce((a, b) => a < b ? a : b);
    final contrast = (lighter + 0.05) / (darker + 0.05);
    expect(contrast, greaterThanOrEqualTo(4.5));
  });
}
