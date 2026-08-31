import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/summary_screen.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/ledger_card.dart';
import 'package:ledger_app/widgets/monthly_summary_chips.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;
  final fixedNow = DateTime(2026, 7, 15);

  setUpAll(() async {
    // 通常時の横並びと大きい文字の折り返しを、実際の字幅で確かめる。
    for (final (family, path) in [
      ('ZenMaruGothic', 'assets/fonts/ZenMaruGothic-Regular.ttf'),
      ('ZenKakuGothicNew', 'assets/fonts/ZenKakuGothicNew-Bold.ttf'),
      ('Outfit', 'assets/fonts/Outfit-SemiBold.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seed(int month, double amount) async {
    if (amount == 0) return;
    await db.insertTransaction(
      TransactionInput(
        memberId: (await db.getMembers()).first.id,
        categoryId: (await db.getCategories()).first.id,
        amount: amount,
        spentAt: DateTime(2026, month, 15),
      ),
    );
  }

  Future<void> pumpSummary(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SummaryProvider(db, clock: () => fixedNow),
        child: MaterialApp(
          theme: ledgerTheme,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
          home: const Scaffold(body: SummaryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder getTotalCard() => find.ancestor(
    of: find.byType(MonthlySummaryChips),
    matching: find.byType(LedgerCard),
  );

  void expectCard(String amount, String change, String count) {
    final card = getTotalCard();
    expect(card, findsOneWidget);
    for (final label in [amount, change, count]) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsOneWidget,
      );
    }
  }

  for (final (current, previous, label) in [
    (1120.0, 1000.0, '先月比 +12.0%'),
    (750.0, 1000.0, '先月比 -25.0%'),
    (1000.0, 1000.0, '先月比 0.0%'),
    (0.0, 1000.0, '先月比 -100.0%'),
    (1000.0, 0.0, '先月比 —'),
    (0.0, 0.0, '先月比 —'),
    (10001.0, 10000.0, '先月比 0.0%'),
    (9999.0, 10000.0, '先月比 0.0%'),
    (1001.0, 1000.0, '先月比 +0.1%'),
  ]) {
    testWidgets('当月$current / 前月$previousを「$label」と表示する', (tester) async {
      await seed(6, previous);
      await seed(7, current);
      await pumpSummary(tester);

      final chips = find.byType(MonthlySummaryChips);
      expect(
        find.descendant(of: chips, matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: chips,
          matching: find.text(current == 0 ? '0件' : '1件'),
        ),
        findsOneWidget,
      );
      if (previous == 0) {
        expect(find.byTooltip('前月の支出が0円のため、先月比は計算できません'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('同じ合計カードの金額直下にオレンジとグレーのピルを横並びにする', (tester) async {
    await seed(6, 1000);
    await seed(7, 500);
    await seed(7, 620);
    await pumpSummary(tester);

    expectCard('¥1,120', '先月比 +12.0%', '2件');
    final change = tester.getRect(find.text('先月比 +12.0%'));
    final count = tester.getRect(find.text('2件'));
    final amount = tester.getRect(
      find.descendant(of: getTotalCard(), matching: find.text('¥1,120')),
    );
    expect(change.top, greaterThan(amount.bottom));
    expect(change.top, count.top);
    expect(change.right, lessThan(count.left));
    for (final (label, color) in [
      ('先月比 +12.0%', ledgerTheme.colorScheme.secondaryContainer),
      ('2件', LedgerTokens.countSurface),
    ]) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, color);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(LedgerTokens.pillRadius),
      );
    }
  });

  testWidgets('月送りと今月への復帰で合計・件数・比較対象が一緒に切り替わる', (tester) async {
    await seed(5, 500);
    await seed(6, 1000);
    await seed(7, 500);
    await seed(7, 620);
    await pumpSummary(tester);
    expectCard('¥1,120', '先月比 +12.0%', '2件');

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expectCard('¥1,000', '先月比 +100.0%', '1件');
    expect(find.text('2026年6月の支出'), findsOneWidget);

    await tester.tap(find.byTooltip('今月に戻る'));
    await tester.pumpAndSettle();
    expectCard('¥1,120', '先月比 +12.0%', '2件');
  });

  testWidgets('年・全期間にはチップを出さず、月へ戻ると再表示する', (tester) async {
    await seed(6, 1000);
    await seed(7, 1120);
    await pumpSummary(tester);
    for (final label in ['年', '全期間']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(MonthlySummaryChips), findsNothing);
      expect(find.textContaining('先月比'), findsNothing);
    }
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expectCard('¥1,120', '先月比 +12.0%', '1件');
  });

  testWidgets('上限金額と大きな増加率も文字倍率2.0でカード内に折り返す', (tester) async {
    await seed(6, 1);
    await seed(7, kMaxAmount);
    await pumpSummary(tester);
    final normalCountHeight = tester.getSize(find.text('1件')).height;
    final normalCardHeight = tester.getSize(getTotalCard()).height;

    await pumpSummary(tester, scale: 2);
    expectCard('¥999,999,999,999', '先月比 +99999999999800.0%', '1件');
    final cardRect = tester.getRect(getTotalCard());
    for (final label in ['先月比 +99999999999800.0%', '1件']) {
      final finder = find.text(label);
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(cardRect.left));
      expect(rect.right, lessThanOrEqualTo(cardRect.right));
      expect(rect.bottom, lessThanOrEqualTo(cardRect.bottom));
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final badgeRect = tester.getRect(
        find.ancestor(of: finder, matching: find.byType(DecoratedBox)).first,
      );
      // 折り返した各行まで実測し、文字の黙った切り落としも検出する。
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: label.length),
      );
      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        // 字形は字間・行高を少し超えることがある。ピルの余白も含めて見る。
        expect(rect.left + box.left, greaterThanOrEqualTo(badgeRect.left));
        expect(rect.left + box.right, lessThanOrEqualTo(badgeRect.right));
        expect(rect.top + box.bottom, lessThanOrEqualTo(badgeRect.bottom));
      }
    }
    expect(
      tester.getSize(find.text('1件')).height,
      greaterThan(normalCountHeight * 1.8),
    );
    expect(
      tester.getSize(getTotalCard()).height,
      greaterThan(normalCardHeight),
    );
    expect(tester.takeException(), isNull);
  });
}
