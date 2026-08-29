import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

/// 割り勘画面を、実端末に近い幅とインメモリ DB で確認する。
void main() {
  late AppDatabase db;
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpSplit(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SummaryProvider(db, clock: () => fixedNow),
        child: MaterialApp(
          theme: ledgerTheme,
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

  testWidgets('濃色の精算カードとテーマの金額書体を使う', (tester) async {
    await insertPayment((await db.getMembers()).first.id, 300);
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
  });

  testWidgets('メンバー行は残高の3色と支払済みの構成比を描く', (tester) async {
    await db.insertMember('みく');
    await db.insertMember('たいち');
    final members = await db.getMembers();

    // 合計 300 円・一人当たり 100 円で、受け取り・均等・支払いを
    // 1 画面にすべて作る。
    await insertPayment(members[0].id, 200);
    await insertPayment(members[1].id, 100);
    await pumpSplit(tester);

    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(LedgerCard), findsNWidgets(2));

    final expected = [
      ('+¥100', '受け取り', LedgerTokens.balancePositive),
      ('¥0', '均等', LedgerTokens.balanceEven),
      ('¥-100', '支払い', LedgerTokens.balanceNegative),
    ];

    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      final row = memberRow(member.id);
      final color = memberColor(member.id);
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
      expect(
        ratioBar.amount,
        i == 0
            ? 200
            : i == 1
            ? 100
            : 0,
      );
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

  testWidgets('kMaxAmount の精算額を 360px 幅で描いても overflow しない', (tester) async {
    await db.insertMember('パートナー');
    final members = await db.getMembers();
    await insertPayment(members.first.id, kMaxAmount);

    await pumpSplit(tester);
    expect(find.text(formatYen(kMaxAmount)), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(memberRow(members.last.id), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
