import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/providers/month_scoped_provider.dart';

/// 表示月の状態遷移だけを見るテスト。DB には触らない。
///
/// この基底クラスは TransactionProvider / SummaryProvider が共有していて、
/// 画面 3 つ（取引・サマリー・割り勘）の月送りがすべてここを通る。
class _FakeMonthScopedProvider extends MonthScopedProvider {
  _FakeMonthScopedProvider({super.clock});

  int fetchCount = 0;
  int notifyCount = 0;

  @override
  Future<void> fetch() async {
    fetchCount++;
  }

  @override
  void notifyListeners() {
    notifyCount++;
    super.notifyListeners();
  }
}

void main() {
  _FakeMonthScopedProvider providerAt(DateTime now) =>
      _FakeMonthScopedProvider(clock: () => now);

  group('初期年月', () {
    test('注入した clock の年月から始まる', () {
      final provider = providerAt(DateTime(2026, 7, 15));

      expect(provider.year, 2026);
      expect(provider.month, 7);
    });

    test('clock 未指定なら実時刻の今月から始まる', () {
      // 既定の挙動が変わっていないことの確認。now を 2 回読む間に月が
      // 変わる可能性があるので、前後どちらかの月に入っていれば良しとする
      final before = DateTime.now();
      final provider = _FakeMonthScopedProvider();
      final after = DateTime.now();

      final actual = DateTime(provider.year, provider.month);
      expect(
        actual,
        anyOf(
          DateTime(before.year, before.month),
          DateTime(after.year, after.month),
        ),
      );
    });
  });

  group('changeMonth', () {
    test('翌月・前月へ動く', () async {
      final provider = providerAt(DateTime(2026, 7, 15));

      await provider.changeMonth(1);
      expect(provider.year, 2026);
      expect(provider.month, 8);

      await provider.changeMonth(-1);
      expect(provider.year, 2026);
      expect(provider.month, 7);
    });

    test('12 月から進めると翌年 1 月に繰り上がる', () async {
      final provider = providerAt(DateTime(2026, 12, 1));

      await provider.changeMonth(1);

      expect(provider.year, 2027);
      expect(provider.month, 1);
    });

    test('1 月から戻すと前年 12 月に繰り下がる', () async {
      final provider = providerAt(DateTime(2026, 1, 1));

      await provider.changeMonth(-1);

      expect(provider.year, 2025);
      expect(provider.month, 12);
    });

    test('月を変えると再取得まで走る', () async {
      // 画面側が fetch を呼び忘れる経路を残さないための約束。
      // changeMonth が状態だけ変えて戻ると、月を送っても一覧が古いままになる
      final provider = providerAt(DateTime(2026, 7, 15));

      await provider.changeMonth(1);

      expect(provider.fetchCount, 1);
      expect(provider.notifyCount, greaterThanOrEqualTo(1));
    });
  });

  group('isCurrentMonth / goToCurrentMonth', () {
    test('clock の月では true、送った先では false', () async {
      final provider = providerAt(DateTime(2026, 7, 15));
      expect(provider.isCurrentMonth, isTrue);

      await provider.changeMonth(-1);
      expect(provider.isCurrentMonth, isFalse);
    });

    test('別の年の同じ月は今月ではない', () {
      final provider = providerAt(DateTime(2026, 7, 15));

      provider.setYearMonth(2025, 7);

      expect(provider.isCurrentMonth, isFalse);
    });

    test('goToCurrentMonth で clock の月に戻り、再取得まで走る', () async {
      final provider = providerAt(DateTime(2026, 7, 15));
      await provider.changeMonth(-3);
      expect(provider.month, 4);

      await provider.goToCurrentMonth();

      expect(provider.year, 2026);
      expect(provider.month, 7);
      expect(provider.isCurrentMonth, isTrue);
      // changeMonth の 1 回 + goToCurrentMonth の 1 回
      expect(provider.fetchCount, 2);
    });
  });

  group('setYearMonth', () {
    test('通知はするが再取得はしない', () {
      // 呼び出し側が任意のタイミングで fetch できるよう、素の setter のまま
      // 残してある（transaction_provider_test.dart がこの形で使っている）
      final provider = providerAt(DateTime(2026, 7, 15));

      provider.setYearMonth(2025, 3);

      expect(provider.year, 2025);
      expect(provider.month, 3);
      expect(provider.fetchCount, 0);
      expect(provider.notifyCount, 1);
    });
  });
}
