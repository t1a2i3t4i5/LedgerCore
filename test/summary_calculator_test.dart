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
  required double amount,
  DateTime? spentAt,
}) {
  return TransactionView(
    id: id,
    memberId: memberId,
    memberName: memberName,
    categoryId: categoryId,
    categoryName: categoryName,
    amount: amount,
    spentAt: spentAt ?? DateTime(2026, 7, 1),
  );
}

void main() {
  group('buildMonthlySummary', () {
    test('カテゴリ別は合計の降順、totalは総和', () {
      final txns = [
        _tx(memberId: 1, memberName: 'A', categoryId: 1, categoryName: '食費', amount: 500),
        _tx(memberId: 1, memberName: 'A', categoryId: 2, categoryName: '交通費', amount: 1500),
        _tx(memberId: 2, memberName: 'B', categoryId: 1, categoryName: '食費', amount: 300),
      ];

      final s = buildMonthlySummary(2026, 7, txns);

      expect(s.total, 2300);
      // 降順: 交通費(1500) > 食費(800)
      expect(s.byCategory.first.categoryName, '交通費');
      expect(s.byCategory.first.total, 1500);
      expect(s.byCategory[1].categoryName, '食費');
      expect(s.byCategory[1].total, 800);
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
      expect(s.byCategory, isEmpty);
      expect(s.byMember, isEmpty);
    });
  });

  group('buildYearlySummary', () {
    test('取引の無い月も 0 で埋めた12件を返す', () {
      final txns = [
        _tx(memberId: 1, memberName: 'A', amount: 1000, spentAt: DateTime(2026, 3, 5)),
        _tx(memberId: 1, memberName: 'A', amount: 500, spentAt: DateTime(2026, 3, 20)),
        _tx(memberId: 1, memberName: 'A', amount: 2000, spentAt: DateTime(2026, 12, 31)),
      ];

      final s = buildYearlySummary(2026, txns);

      expect(s.byMonth.length, 12);
      expect(s.byMonth.first.month, 1);
      expect(s.byMonth.first.year, 2026);
      expect(s.byMonth.first.total, 0);
      expect(s.byMonth[2].month, 3);
      expect(s.byMonth[2].total, 1500);
      expect(s.byMonth.last.total, 2000);
      expect(s.total, 3500);
    });

    test('他の年の取引は集計に含めない', () {
      final txns = [
        _tx(memberId: 1, memberName: 'A', amount: 1000, spentAt: DateTime(2025, 12, 31)),
        _tx(memberId: 1, memberName: 'A', amount: 300, spentAt: DateTime(2026, 1, 1)),
        _tx(memberId: 1, memberName: 'A', amount: 700, spentAt: DateTime(2027, 1, 1)),
      ];

      final s = buildYearlySummary(2026, txns);

      expect(s.total, 300);
      expect(s.byMonth.first.total, 300);
      expect(s.byMonth.skip(1).every((p) => p.total == 0), isTrue);
    });

    test('カテゴリ別は年合計の降順', () {
      final txns = [
        _tx(memberId: 1, memberName: 'A', categoryId: 1, categoryName: '食費', amount: 400, spentAt: DateTime(2026, 2, 1)),
        _tx(memberId: 1, memberName: 'A', categoryId: 1, categoryName: '食費', amount: 400, spentAt: DateTime(2026, 9, 1)),
        _tx(memberId: 1, memberName: 'A', categoryId: 2, categoryName: '交通費', amount: 500, spentAt: DateTime(2026, 5, 1)),
      ];

      final s = buildYearlySummary(2026, txns);

      expect(s.byCategory.first.categoryName, '食費');
      expect(s.byCategory.first.total, 800);
      expect(s.byCategory[1].categoryName, '交通費');
    });

    test('取引が無くても12件返り total は 0', () {
      final s = buildYearlySummary(2026, []);
      expect(s.byMonth.length, 12);
      expect(s.total, 0);
      expect(s.byCategory, isEmpty);
    });
  });

  group('buildYearlyTotals', () {
    test('取引のある年だけを昇順で返す', () {
      final txns = [
        _tx(memberId: 1, memberName: 'A', amount: 100, spentAt: DateTime(2026, 5, 1)),
        _tx(memberId: 1, memberName: 'A', amount: 200, spentAt: DateTime(2024, 8, 1)),
        _tx(memberId: 1, memberName: 'A', amount: 300, spentAt: DateTime(2026, 1, 1)),
      ];

      final totals = buildYearlyTotals(txns);

      expect(totals.map((p) => p.year), [2024, 2026]);
      expect(totals.first.total, 200);
      expect(totals.last.total, 400);
      // 年別集計では月は持たない
      expect(totals.first.month, isNull);
    });

    test('取引が無ければ空リスト', () {
      expect(buildYearlyTotals([]), isEmpty);
    });
  });

  group('buildSplit', () {
    final members2 = [
      const HouseholdMember(id: 1, name: 'A'),
      const HouseholdMember(id: 2, name: 'B'),
    ];

    test('2人: 片方が全額払ったら「支払う」文言', () {
      final txns = [_tx(memberId: 1, memberName: 'A', amount: 1000)];
      final split = buildSplit(2026, 7, txns, members2);

      expect(split.total, 1000);
      expect(split.fairShare, 500);
      final a = split.members.firstWhere((m) => m.memberId == 1);
      final b = split.members.firstWhere((m) => m.memberId == 2);
      expect(a.balance, 500);
      expect(b.balance, -500);
      expect(split.settlement, 'B → A に 500 円支払う');
    });

    test('均等に払っていれば精算不要', () {
      final txns = [
        _tx(memberId: 1, memberName: 'A', amount: 500),
        _tx(memberId: 2, memberName: 'B', amount: 500),
      ];
      final split = buildSplit(2026, 7, txns, members2);
      expect(split.settlement, '精算不要');
    });

    test('3人以上は一覧形式で支払い必要額を列挙', () {
      final members3 = [
        const HouseholdMember(id: 1, name: 'A'),
        const HouseholdMember(id: 2, name: 'B'),
        const HouseholdMember(id: 3, name: 'C'),
      ];
      final txns = [_tx(memberId: 1, memberName: 'A', amount: 3000)];
      final split = buildSplit(2026, 7, txns, members3);

      expect(split.total, 3000);
      expect(split.fairShare, 1000);
      final lines = split.settlement.split('\n');
      expect(lines.length, 2);
      expect(lines, contains('B は 1000 円の支払いが必要'));
      expect(lines, contains('C は 1000 円の支払いが必要'));
    });

    test('支出0のメンバーも均等割の対象になる', () {
      final txns = [_tx(memberId: 1, memberName: 'A', amount: 900)];
      final split = buildSplit(2026, 7, txns, members2);
      // 900 / 2 = 450
      expect(split.fairShare, 450);
      final b = split.members.firstWhere((m) => m.memberId == 2);
      expect(b.paid, 0);
      expect(b.balance, -450);
    });

    test('fairShare は小数第2位で四捨五入（HALF_UP）', () {
      final members3 = [
        const HouseholdMember(id: 1, name: 'A'),
        const HouseholdMember(id: 2, name: 'B'),
        const HouseholdMember(id: 3, name: 'C'),
      ];
      final txns = [_tx(memberId: 1, memberName: 'A', amount: 100)];
      final split = buildSplit(2026, 7, txns, members3);
      // 100 / 3 = 33.333... -> 33.33
      expect(split.fairShare, 33.33);
    });
  });
}
