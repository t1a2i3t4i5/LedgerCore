import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/split_screen.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/amount_format.dart';
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:ledger_app/widgets/ledger_card.dart';
import 'package:ledger_app/widgets/ratio_bar.dart';
import 'package:provider/provider.dart';
import '../seed.dart';

/// 精算画面を、実端末に近い幅とインメモリ DB で確認する。
void main() {
  late AppDatabase db;
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // onCreate はメンバーを投入しないので、テスト側で用意する（#144）
    await seedMembers(db);
  });
  tearDown(() async => db.close());

  Future<void> pumpSplit(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
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
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
          home: const Scaffold(body: SplitScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> insertPayment(int memberId, double amount) async {
    final categoryId = (await db.getCategories()).first.id;
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: categoryId,
        amount: amount,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ),
    );
  }

  Finder memberRow(int memberId) =>
      find.byKey(ValueKey('member-balance-$memberId'));

  Text memberBalanceText(WidgetTester tester, int memberId) => tester
      .widget<Text>(find.byKey(ValueKey('member-balance-amount-$memberId')));

  testWidgets('1人状態は精算に2人必要だと案内する', (tester) async {
    await pumpSplit(tester);

    expect(find.text('精算にはメンバーが2人必要です'), findsOneWidget);
    expect(find.byKey(const ValueKey('settlement-card')), findsNothing);
    expect(find.byKey(const ValueKey('summary-amount-合計')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('濃色の精算カードとテーマの金額書体を使う', (tester) async {
    await db.insertMember('パートナー');
    await pumpSplit(tester);

    final settlement = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('settlement-card')),
    );
    final decoration = settlement.decoration as BoxDecoration;
    expect(decoration.color, ledgerTheme.colorScheme.primary);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(LedgerTokens.cardRadiusLarge),
    );

    final title = tester.widget<Text>(find.text('精算方法'));
    final body = tester.widget<Text>(find.text('精算不要'));
    expect(title.style?.color, ledgerTheme.colorScheme.onPrimary);
    expect(body.style?.color, ledgerTheme.colorScheme.onPrimary);

    for (final label in ['合計', '一人当たり']) {
      final amount = tester.widget<Text>(
        find.byKey(ValueKey('summary-amount-$label')),
      );
      expect(amount.style?.fontFamily, LedgerTokens.amountRow.fontFamily);
      expect(amount.style?.fontSize, LedgerTokens.amountRow.fontSize);
    }
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('summary-amount-一人当たり')))
          .data,
      '¥0',
    );
  });

  testWidgets('メンバー行は残高の2色と支払済みの構成比を描く', (tester) async {
    await db.insertMember('みく');
    var members = await db.getMembers();
    await db.updateMemberColor(members.first.id, memberPalette.last.toARGB32());
    members = await db.getMembers();

    // 合計 300 円・一人当たり 150 円で、受け取りと支払いを作る。
    await insertPayment(members[0].id, 200);
    await insertPayment(members[1].id, 100);
    await pumpSplit(tester);

    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(LedgerCard), findsNWidgets(2));

    final expected = [
      ('+¥50', '受け取り', LedgerTokens.balancePositive),
      ('¥-50', '支払い', LedgerTokens.balanceNegative),
    ];

    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      final row = memberRow(member.id);
      final color = memberColor(member.id, colorValue: member.colorValue);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(expected[i].$1)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(expected[i].$2)),
        findsOneWidget,
      );
      expect(memberBalanceText(tester, member.id).style?.color, expected[i].$3);

      final paid = tester.widget<Text>(
        find.byKey(ValueKey('member-paid-${member.id}')),
      );
      expect(paid.style?.fontFamily, LedgerTokens.amountSmall.fontFamily);
      expect(paid.style?.fontSize, LedgerTokens.amountSmall.fontSize);

      final dot = tester.widget<CircleAvatar>(
        find.descendant(of: row, matching: find.byType(CircleAvatar)),
      );
      expect(dot.backgroundColor, color);

      final ratioBar = tester.widget<RatioBar>(
        find.descendant(of: row, matching: find.byType(RatioBar)),
      );
      expect(ratioBar.amount, i == 0 ? 200 : 100);
      expect(ratioBar.total, 300);
      expect(ratioBar.color, color);
      expect(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) => widget is ColoredBox && widget.color == color,
          ),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('同額を立て替えた2人は均等色で表示する', (tester) async {
    await db.insertMember('みく');
    final members = await db.getMembers();
    for (final member in members) {
      await insertPayment(member.id, 100);
    }

    await pumpSplit(tester);

    for (final member in members) {
      final row = memberRow(member.id);
      expect(
        find.descendant(of: row, matching: find.text('¥0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('均等')),
        findsOneWidget,
      );
      expect(
        memberBalanceText(tester, member.id).style?.color,
        LedgerTokens.balanceEven,
      );
    }
  });

  testWidgets('日常的な偶数額を1つの負担額として1行に収める', (tester) async {
    await db.insertMember('パートナー');
    await insertPayment((await db.getMembers()).first.id, 123456);

    await pumpSplit(tester);

    final total = find.byKey(const ValueKey('summary-amount-合計'));
    final fitted = find.byKey(const ValueKey('summary-amount-fitted-合計'));
    final paragraph = tester.renderObject<RenderParagraph>(total);
    final intrinsicWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
    final availableWidth = tester.getSize(fitted).width;

    expect(intrinsicWidth, greaterThan(availableWidth));
    expect(tester.getRect(total).width, lessThanOrEqualTo(availableWidth));
    expect(tester.widget<Text>(total).maxLines, 1);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('summary-amount-一人当たり')))
          .data,
      '¥61,728',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('奇数の上限額と2つの負担額を文字倍率2.0でも省略しない', (tester) async {
    await db.insertMember('パートナー');
    final members = await db.getMembers();
    await insertPayment(members.first.id, kMaxAmount);
    final shares =
        '${formatYen((kMaxAmount / 2).floorToDouble())}・'
        '${formatYen((kMaxAmount / 2).ceilToDouble())}';

    await pumpSplit(tester, textScale: 2);

    expect(find.text(formatYen(kMaxAmount)), findsOneWidget);
    expect(find.text(shares), findsOneWidget);
    expect(find.byType(FittedBox), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    for (final label in ['合計', '一人当たり']) {
      final amount = find.byKey(ValueKey('summary-amount-$label'));
      final fitted = find.byKey(ValueKey('summary-amount-fitted-$label'));
      final paragraph = tester.renderObject<RenderParagraph>(amount);
      final intrinsicWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
      final availableWidth = tester.getSize(fitted).width;

      expect(intrinsicWidth, greaterThan(availableWidth));
      expect(tester.getRect(amount).width, lessThanOrEqualTo(availableWidth));
      expect(tester.widget<Text>(amount).maxLines, 1);
    }

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('パートナー → 自分 に ¥500,000,000,000 支払う'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(memberRow(members.last.id), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
