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
    expect(
      ledgerTheme.appBarTheme.systemOverlayStyle,
      ledgerSystemUiOverlayStyle,
    );
    expect(ledgerSystemUiOverlayStyle.statusBarIconBrightness, Brightness.dark);
    expect(ledgerSystemUiOverlayStyle.statusBarBrightness, Brightness.light);
    expect(ledgerSystemUiOverlayStyle.systemNavigationBarColor, isNull);
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

  test('強調の書体は Zen Kaku Gothic New の Bold', () {
    expect(LedgerTokens.heading.fontFamily, 'ZenKakuGothicNew');
    expect(LedgerTokens.heading.fontWeight, FontWeight.w700);
  });

  test('本文書体へ太字を要求するスロットが無い', () {
    // Zen Maru Gothic は Regular だけを同梱する（test/bundled_fonts_test.dart）。
    // ラベルの w500 は既存の代替描画を許容する。明示的な強調に当たる
    // w600 以上は同梱の見出し書体で出す
    final textTheme = ledgerTheme.textTheme;
    final slots = <String, TextStyle?>{
      'displayLarge': textTheme.displayLarge,
      'displayMedium': textTheme.displayMedium,
      'displaySmall': textTheme.displaySmall,
      'headlineLarge': textTheme.headlineLarge,
      'headlineMedium': textTheme.headlineMedium,
      'headlineSmall': textTheme.headlineSmall,
      'titleLarge': textTheme.titleLarge,
      'titleMedium': textTheme.titleMedium,
      'titleSmall': textTheme.titleSmall,
      'bodyLarge': textTheme.bodyLarge,
      'bodyMedium': textTheme.bodyMedium,
      'bodySmall': textTheme.bodySmall,
      'labelLarge': textTheme.labelLarge,
      'labelMedium': textTheme.labelMedium,
      'labelSmall': textTheme.labelSmall,
    };

    for (final MapEntry(key: name, value: style) in slots.entries) {
      // fontFamily 未指定のスロットは ThemeData.fontFamily を継ぐので本文書体
      final usesBodyFont =
          style?.fontFamily == null || style?.fontFamily == 'ZenMaruGothic';
      if (!usesBodyFont) continue;
      expect(
        style?.fontWeight?.value ?? FontWeight.w400.value,
        lessThanOrEqualTo(FontWeight.w500.value),
        reason: '$name が本文書体に太字を要求している',
      );
    }
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

  test('FilledButton の形状はテーマで StadiumBorder に統一する', () {
    expect(
      ledgerTheme.filledButtonTheme.style?.shape?.resolve({}),
      isA<StadiumBorder>(),
    );
  });
}
