import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/summary_calculator.dart';
import 'package:ledger_app/models/household_member.dart';
import 'package:ledger_app/models/transaction.dart';

TransactionView _tx({
  int id = 1,
  required int memberId,
  required String memberName,
  int categoryId = 1,
  String categoryName = '食費',
  int? categoryColorValue,
  int? categorySortOrder,
  bool categoryIsFixed = false,
  required double amount,
  DateTime? spentAt,
}) {
  return TransactionView(
    id: id,
    memberId: memberId,
    memberName: memberName,
    categoryId: categoryId,
    categoryName: categoryName,
    categoryColorValue: categoryColorValue,
    categorySortOrder: categorySortOrder,
    categoryIsFixed: categoryIsFixed,
    amount: amount,
    spentAt: spentAt ?? DateTime(2026, 7, 1),
  );
}

void main() {
  group('buildMonthlySummary', () {
    test('カテゴリ別は保存順で、色を引き継ぎ、totalは総和', () {
      final txns = [
        _tx(
          memberId: 1,
          memberName: 'A',
          categoryId: 1,
          categoryName: '食費',
          categorySortOrder: 1,
          amount: 500,
        ),
        _tx(
          memberId: 1,
          memberName: 'A',
          categoryId: 2,
          categoryName: '交通費',
          categoryColorValue: 0xFF3D7F78,
          categorySortOrder: 0,
          amount: 1500,
        ),
        _tx(
          memberId: 2,
          memberName: 'B',
          categoryId: 1,
          categoryName: '食費',
          categorySortOrder: 1,
          amount: 300,
        ),
      ];

      final s = buildMonthlySummary(2026, 7, txns);

      expect(s.total, 2300);
      expect(s.transactionCount, 3);
      // 金額ではなく保存順: 交通費(0) → 食費(1)
      expect(s.byCategory.first.categoryName, '交通費');
      expect(s.byCategory.first.total, 1500);
      expect(s.byCategory.first.categoryColorValue, 0xFF3D7F78);
      expect(s.byCategory[1].categoryName, '食費');
      expect(s.byCategory[1].total, 800);
    });

    test('固定カテゴリは保存順より後、内訳の最後に来る', () {
      final txns = [
        _tx(
          memberId: 1,
          memberName: 'A',
          categoryId: 9,
          categoryName: 'その他',
          // 受け皿は既定カテゴリの並びで先に作られるので順序値は小さい
          categorySortOrder: 0,
          categoryIsFixed: true,
          amount: 100,
        ),
        _tx(
          memberId: 1,
          memberName: 'A',
          categoryId: 1,
          categoryName: 'あとで足したカテゴリ',
          categorySortOrder: 5,
          amount: 200,
        ),
      ];

      final s = buildMonthlySummary(2026, 7, txns);

      expect(s.byCategory.map((item) => item.categoryName), [
        'あとで足したカテゴリ',
        'その他',
      ]);
    });

    test('メンバー別に集計される', () {
      final txns = [
        _tx(memberId: 1, memberName: 'A', amount: 500),
        _tx(memberId: 1, memberName: 'A', amount: 500),
        _tx(memberId: 2, memberName: 'B', amount: 300),
      ];

      final s = buildMonthlySummary(2026, 7, txns);
      final byMember = {for (final u in s.byMember) u.memberName: u.total};
      expect(byMember['A'], 1000);
      expect(byMember['B'], 300);
    });

    test('取引が無ければ total は 0', () {
      final s = buildMonthlySummary(2026, 7, []);
      expect(s.total, 0);
      expect(s.transactionCount, 0);
      expect(s.byCategory, isEmpty);
      expect(s.byMember, isEmpty);
    });
  });

  group('buildMonthlyComparison', () {
    for (final (currentAmount, previousAmount, expectedChange) in [
      (1120.0, 1000.0, 120.0),
      (750.0, 1000.0, -250.0),
      (1000.0, 1000.0, 0.0),
      (0.0, 1000.0, -1000.0),
      (1000.0, 0.0, 1000.0),
      (0.0, 0.0, 0.0),
      (kMaxAmount, 1.0, kMaxAmount - 1),
    ]) {
      test('当月$currentAmount / 前月$previousAmountの差額と前月合計を返す', () {
        final current = buildMonthlySummary(2026, 7, [
          if (currentAmount > 0)
            _tx(memberId: 1, memberName: 'A', amount: currentAmount),
        ]);
        final previous = buildMonthlySummary(2026, 6, [
          if (previousAmount > 0)
            _tx(memberId: 1, memberName: 'A', amount: previousAmount),
        ]);

        final comparison = buildMonthlyComparison(current, previous);

        expect(comparison.previousTotal, previousAmount);
        expect(comparison.amountChange, expectedChange);
      });
    }
  });

  group('buildSplit', () {
    final members2 = [
      const HouseholdMember(id: 1, name: 'A'),
      const HouseholdMember(id: 2, name: 'B'),
    ];

    test('2人: 片方が全額払ったら送金元・送金先・金額を返す', () {
      final txns = [_tx(memberId: 1, memberName: 'A', amount: 1000)];
      final split = buildSplit(2026, 7, txns, members2);

      expect(split.total, 1000);
      expect(split.pair?.lowerShare, 500);
      expect(split.pair?.higherShare, 500);
      final a = split.members.firstWhere((m) => m.memberId == 1);
      final b = split.members.firstWhere((m) => m.memberId == 2);
      expect(a.share, 500);
      expect(b.share, 500);
      expect(a.balance, 500);
      expect(b.balance, -500);
      expect(split.pair?.settlement?.from.memberId, 2);
      expect(split.pair?.settlement?.to.memberId, 1);
      expect(split.pair?.settlement?.amount, 500);
    });

    test('均等に払っていれば精算不要', () {
      final txns = [
        _tx(memberId: 1, memberName: 'A', amount: 500),
        _tx(memberId: 2, memberName: 'B', amount: 500),
      ];
      final split = buildSplit(2026, 7, txns, members2);
      expect(split.pair?.settlement, isNull);
    });

    test('支出0のメンバーも均等割の対象になる', () {
      final txns = [_tx(memberId: 1, memberName: 'A', amount: 900)];
      final split = buildSplit(2026, 7, txns, members2);
      expect(split.pair?.lowerShare, 450);
      expect(split.pair?.higherShare, 450);
      final b = split.members.firstWhere((m) => m.memberId == 2);
      expect(b.paid, 0);
      expect(b.balance, -450);
    });

    test('奇数円は立替額の少ない側が1円多く負担する', () {
      for (final payments in [
        (1001.0, 0.0, 501.0),
        (501.0, 500.0, 1.0),
        (0.0, 1001.0, 501.0),
      ]) {
        final txns = [
          if (payments.$1 > 0)
            _tx(memberId: 1, memberName: 'A', amount: payments.$1),
          if (payments.$2 > 0)
            _tx(memberId: 2, memberName: 'B', amount: payments.$2),
        ];
        final split = buildSplit(2026, 7, txns, members2);

        expect(split.pair?.lowerShare, 500);
        expect(split.pair?.higherShare, 501);
        final lowerPaid = split.members.reduce(
          (a, b) => a.paid < b.paid ? a : b,
        );
        final higherPaid = split.members.reduce(
          (a, b) => a.paid > b.paid ? a : b,
        );
        expect(lowerPaid.share, 501);
        expect(higherPaid.share, 500);
        expect(split.pair?.settlement?.from.memberId, lowerPaid.memberId);
        expect(split.pair?.settlement?.to.memberId, higherPaid.memberId);
        expect(split.pair?.settlement?.amount, payments.$3);
      }
    });

    test('2人でない場合は負担額と精算を算出しない', () {
      final members = [const HouseholdMember(id: 1, name: 'A')];
      final txns = [_tx(memberId: 1, memberName: 'A', amount: 100)];
      final split = buildSplit(2026, 7, txns, members);

      expect(split.pair, isNull);
      expect(split.members.single.share, isNull);
      expect(split.members.single.balance, isNull);
    });

    test('3人以上の場合も負担額と精算を算出しない', () {
      final members = [
        const HouseholdMember(id: 1, name: 'A'),
        const HouseholdMember(id: 2, name: 'B'),
        const HouseholdMember(id: 3, name: 'C'),
      ];
      final txns = [_tx(memberId: 1, memberName: 'A', amount: 3000)];
      final split = buildSplit(2026, 7, txns, members);

      expect(split.total, 3000);
      expect(split.pair, isNull);
      expect(split.members, hasLength(3));
      expect(split.members.map((member) => member.paid), [3000, 0, 0]);
      expect(split.members.every((member) => member.share == null), isTrue);
      expect(split.members.every((member) => member.balance == null), isTrue);
    });
  });
}
