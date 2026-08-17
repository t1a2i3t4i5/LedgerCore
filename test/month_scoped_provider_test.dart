import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/providers/month_scoped_provider.dart';

/// 表示月の状態遷移だけを見るテスト。DB には触らない。
///
/// この基底クラスは TransactionProvider / SummaryProvider が共有していて、
/// 画面 3 つ（取引・サマリー・割り勘）の月送りがすべてここを通る。
class _FakeMonthScopedProvider extends MonthScopedProvider {
  _FakeMonthScopedProvider({super.clock});

  /// fetch が走った時点の表示月。回数だけでなく「どの月で読んだか」を残す。
  ///
  /// 回数しか数えないと、表示月を変える前に fetch する実装（＝古い月の
  /// データを読んでから月表示だけ進む）を素通ししてしまう
  final List<DateTime> fetchedMonths = [];
  int notifyCount = 0;

  @override
  Future<void> fetch() async {
    fetchedMonths.add(DateTime(year, month));
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

    test('1 か月より大きく送っても正しい月に着く', () async {
      final provider = providerAt(DateTime(2026, 7, 15));

      await provider.changeMonth(-9);

      expect(provider.year, 2025);
      expect(provider.month, 10);
    });

    test('再取得は「送った先の月」で走る', () async {
      // 画面側が fetch を呼び忘れる経路を残さないための約束。
      // 回数だけ見ると、表示月を変える前に fetch する実装（＝古い月を
      // 読んでから月表示だけ進む）を見逃す。CLAUDE.md が防ぐと書いている
      // 「月を送ったのに中身が前の月のまま」がまさにこれ
      final provider = providerAt(DateTime(2026, 7, 15));

      await provider.changeMonth(1);

      expect(provider.fetchedMonths, [DateTime(2026, 8)]);
    });

    test('月をまたぐ通知はちょうど 1 回', () async {
      // 緩い matcher にすると通知の重複発火（＝余計なリビルド）を見逃す
      final provider = providerAt(DateTime(2026, 7, 15));

      await provider.changeMonth(1);

      expect(provider.notifyCount, 1);
    });
  });

  group('goToMonth', () {
    test('指定した年月へ移り、その月で再取得する', () async {
      // 保存先の月へ飛ぶ導線（取引追加後の「その月を表示」）が通る経路。
      // 表示月だけ変えて再取得しない実装だと、飛んだ先の一覧が空のままになる
      final provider = providerAt(DateTime(2026, 7, 15));

      await provider.goToMonth(2025, 11);

      expect(provider.year, 2025);
      expect(provider.month, 11);
      expect(provider.fetchedMonths, [DateTime(2025, 11)]);
    });

    test('範囲外の月は繰り上げ・繰り下げして正規化する', () async {
      final provider = providerAt(DateTime(2026, 7, 15));

      await provider.goToMonth(2026, 13);

      expect(provider.year, 2027);
      expect(provider.month, 1);
      expect(provider.fetchedMonths, [DateTime(2027, 1)]);
    });

    test('同じ月を指定しても再取得する', () async {
      // 「その月を表示」を押した先が今の表示月と同じでも、押した以上は
      // 最新の状態を見せる。黙って何もしないと壊れているように見える
      final provider = providerAt(DateTime(2026, 7, 15));

      await provider.goToMonth(2026, 7);

      expect(provider.fetchedMonths, [DateTime(2026, 7)]);
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

    test('goToCurrentMonth で clock の月に戻り、その月で再取得する', () async {
      final provider = providerAt(DateTime(2026, 7, 15));
      await provider.changeMonth(-3);
      expect(provider.month, 4);

      await provider.goToCurrentMonth();

      expect(provider.year, 2026);
      expect(provider.month, 7);
      expect(provider.isCurrentMonth, isTrue);
      expect(provider.fetchedMonths, [DateTime(2026, 4), DateTime(2026, 7)]);
    });

    test('clock は呼ぶたびに評価される（起動時の値を握らない）', () async {
      // Clock を関数型にしてある理由。コンストラクタで 1 回読んでキャッシュ
      // すると、アプリを開いたまま日付が変わった端末で「今月に戻る」が
      // 押せない／押しても前の月に戻る、という静かな壊れ方をする
      var now = DateTime(2026, 7, 31, 23, 59);
      final provider = _FakeMonthScopedProvider(clock: () => now);
      expect(provider.isCurrentMonth, isTrue);

      // 日付をまたぐ
      now = DateTime(2026, 8, 1, 0, 1);

      expect(provider.isCurrentMonth, isFalse);
      await provider.goToCurrentMonth();
      expect(provider.year, 2026);
      expect(provider.month, 8);
    });
  });

  // 年の軸はこのクラスに持たせない。`_year` は表示月の一部で、動かせば
  // fetch の対象月ごと変わる（＝Provider を共有している割り勘タブを巻き込む）。
  // 年単位の表示は SummaryProvider が独立した軸として持つので、
  // そちらのテストは test/summary_provider_test.dart にある。

  group('setYearMonth', () {
    test('通知はするが再取得はしない', () {
      // 呼び出し側が任意のタイミングで fetch できるよう、素の setter のまま
      // 残してある（transaction_provider_test.dart がこの形で使っている）
      final provider = providerAt(DateTime(2026, 7, 15));

      provider.setYearMonth(2025, 3);

      expect(provider.year, 2025);
      expect(provider.month, 3);
      expect(provider.fetchedMonths, isEmpty);
      expect(provider.notifyCount, 1);
    });

    test('範囲外の月は繰り上げ・繰り下げして正規化する', () async {
      // 正規化しないと getTransactionsByMonth(2026, 13) が 2027 年 1 月の
      // データを返し、ヘッダだけ「2026年13月」になる
      final provider = providerAt(DateTime(2026, 7, 15));

      provider.setYearMonth(2026, 13);
      expect(provider.year, 2027);
      expect(provider.month, 1);

      provider.setYearMonth(2026, 0);
      expect(provider.year, 2025);
      expect(provider.month, 12);
    });
  });
}
