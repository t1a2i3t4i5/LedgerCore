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
    expect(
      ledgerTheme.appBarTheme.backgroundColor,
      ledgerTheme.colorScheme.surface,
    );
    expect(
      ledgerTheme.appBarTheme.foregroundColor,
      ledgerTheme.colorScheme.onSurface,
    );
    expect(ledgerTheme.appBarTheme.scrolledUnderElevation, 0);
  });

  test('NavigationBar は白い面とアプリコットの選択色を使う', () {
    final theme = ledgerTheme.navigationBarTheme;
    final selectedIcon = theme.iconTheme?.resolve({WidgetState.selected});
    final unselectedIcon = theme.iconTheme?.resolve({});
    final selectedLabel = theme.labelTextStyle?.resolve({WidgetState.selected});
    final unselectedLabel = theme.labelTextStyle?.resolve({});

    expect(
      theme.backgroundColor,
      ledgerTheme.colorScheme.surfaceContainerLowest,
    );
    expect(theme.indicatorColor, ledgerTheme.colorScheme.secondaryContainer);
    expect(selectedIcon?.color, ledgerTheme.colorScheme.onSecondaryContainer);
    expect(unselectedIcon?.color, ledgerTheme.colorScheme.onSurfaceVariant);
    expect(selectedLabel?.color, ledgerTheme.colorScheme.onSurface);
    expect(unselectedLabel?.color, ledgerTheme.colorScheme.onSurfaceVariant);
  });

  test('中見出しは Zen Kaku Gothic New を使う', () {
    expect(ledgerTheme.textTheme.titleMedium?.fontFamily, 'ZenKakuGothicNew');
  });

  test('大きな金額は Outfit を使う', () {
    expect(LedgerTokens.amountLarge.fontFamily, 'Outfit');
  });

  testWidgets('AlertDialog の解決後の面は白く角丸24になる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ledgerTheme,
        home: const Scaffold(
          body: AlertDialog(title: Text('確認'), content: Text('内容')),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Material),
      ),
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(material.color, ledgerTheme.colorScheme.surfaceContainerLow);
    expect(shape.borderRadius, BorderRadius.circular(LedgerTokens.cardRadius));
  });

  test('BottomSheet の上辺は角丸28になる', () {
    final shape = ledgerTheme.bottomSheetTheme.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(LedgerTokens.cardRadiusLarge),
      ),
    );
  });

  test('FilterChip はピル形状で、選択面の文字が AA コントラストを満たす', () {
    final chipTheme = ledgerTheme.chipTheme;
    final selectedTextColor =
        WidgetStateProperty.resolveAs<Color?>(chipTheme.labelStyle!.color, {
          WidgetState.selected,
        })!;
    final selectedColor = chipTheme.selectedColor!;
    final selectedSide =
        WidgetStateProperty.resolveAs<BorderSide?>(chipTheme.side, {
          WidgetState.selected,
        })!;
    final unselectedSide =
        WidgetStateProperty.resolveAs<BorderSide?>(chipTheme.side, {})!;
    final lighter =
        selectedTextColor.computeLuminance() > selectedColor.computeLuminance()
            ? selectedTextColor
            : selectedColor;
    final darker =
        identical(lighter, selectedTextColor)
            ? selectedColor
            : selectedTextColor;
    final contrast =
        (lighter.computeLuminance() + 0.05) /
        (darker.computeLuminance() + 0.05);

    expect(chipTheme.shape, isA<StadiumBorder>());
    expect(chipTheme.showCheckmark, isFalse);
    expect(selectedSide.color, ledgerTheme.colorScheme.onSurface);
    expect(selectedSide.width, 2);
    expect(unselectedSide, BorderSide.none);
    expect(
      chipTheme.labelStyle?.fontFamily,
      ledgerTheme.textTheme.labelLarge?.fontFamily,
    );
    expect(
      chipTheme.labelStyle?.fontWeight,
      ledgerTheme.textTheme.labelLarge?.fontWeight,
    );
    expect(
      chipTheme.labelStyle?.letterSpacing,
      ledgerTheme.textTheme.labelLarge?.letterSpacing,
    );
    expect(
      chipTheme.labelStyle?.height,
      ledgerTheme.textTheme.labelLarge?.height,
    );
    expect(
      chipTheme.backgroundColor,
      ledgerTheme.colorScheme.surfaceContainerHighest,
    );
    expect(selectedColor, ledgerTheme.colorScheme.secondaryContainer);
    expect(contrast, greaterThanOrEqualTo(4.5));
  });
}
