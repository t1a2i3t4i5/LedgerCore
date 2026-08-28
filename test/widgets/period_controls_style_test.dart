import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/month_selector.dart';

void main() {
  Future<void> pumpSelector(
    WidgetTester tester, {
    double textScale = 1,
    bool todayEnabled = true,
  }) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ledgerTheme,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: MonthSelector(
              year: 2026,
              month: 7,
              onPrev: () {},
              onNext: () {},
              onToday: todayEnabled ? () {} : null,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('月セレクタは二段見出しと 38px の角丸ボタンを描く', (tester) async {
    await pumpSelector(tester);

    final title = tester.widget<Text>(find.text('2026年7月'));
    final spans = (title.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.text, '7月');
    expect(spans.first.style?.fontSize, 38);
    expect(spans.last.text, '\n2026');
    expect(spans.last.style?.fontFamily, LedgerTokens.periodYear.fontFamily);
    expect(spans.last.style?.fontSize, 16);
    expect(find.text('今月'), findsOneWidget);

    expect(
      tester.widget<Text>(find.text('今月')).style?.color,
      ledgerTheme.colorScheme.onPrimary,
    );

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

  testWidgets('文字倍率 2.0 でも「今月」の 2 文字が欠けない', (tester) async {
    await pumpSelector(tester, textScale: 2);

    expect(
      tester.renderObject<RenderParagraph>(find.text('今月')).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('「今月」は無効時に薄い面へ切り替わる', (tester) async {
    await pumpSelector(tester, todayEnabled: false);

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('今月に戻る'),
        matching: find.byType(IconButton),
      ),
    );
    final style = button.style!;
    final enabledBackground = style.backgroundColor!.resolve({});
    final disabledBackground = style.backgroundColor!.resolve({
      WidgetState.disabled,
    });

    expect(enabledBackground, ledgerTheme.colorScheme.primary);
    expect(disabledBackground, ledgerTheme.colorScheme.primaryContainer);
    expect(disabledBackground, isNot(enabledBackground));
    expect(
      tester.widget<Text>(find.text('今月')).style?.color,
      ledgerTheme.colorScheme.onPrimaryContainer,
    );
  });

  test('期間セグメントは白い選択面と onSurface の文字を使う', () {
    final style = ledgerTheme.segmentedButtonTheme.style!;
    final selected = {WidgetState.selected};
    final background = style.backgroundColor!.resolve(selected)!;
    final foreground = style.foregroundColor!.resolve(selected)!;

    expect(background, ledgerTheme.colorScheme.surfaceContainerLowest);
    expect(foreground, ledgerTheme.colorScheme.onSurface);
    expect(
      style.side!.resolve(selected),
      BorderSide(color: ledgerTheme.colorScheme.outlineVariant),
    );

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
