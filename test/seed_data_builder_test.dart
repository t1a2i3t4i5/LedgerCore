import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/models/transaction.dart';

import '../tool/seed_data_builder.dart';

/// 開発用シードデータの生成（`tool/seed_data_builder.dart`）を DB なしで検証する。
///
/// 目的は「壊れた値を DB へ流して途中で落ちる」のを防ぐこと。`transactions` の
/// CHECK（正の整数・上限）と、未来の取引を作らないことをここで押さえる。
/// 実際の投入は `tool/seed_dev_data.dart` が行う。
void main() {
  // 基準日は固定する。DateTime.now() を使うと当月の日数で結果が揺れる。
  final now = DateTime(2026, 9, 8, 12, 30);
  const categoryIds = {
    '食費': 1,
    '日用品': 2,
    '交通費': 3,
    '光熱費': 4,
    '通信費': 5,
    '住居費': 6,
    '医療費': 7,
    '娯楽費': 8,
    '衣服': 9,
    'その他': 10,
  };
  const memberIds = [1, 2];

  List<SeedTransaction> build({int months = 12, int seed = 20260908}) =>
      buildSeedTransactions(
        now: now,
        categoryIdsByName: categoryIds,
        memberIds: memberIds,
        months: months,
        seed: seed,
      );

  test('金額はすべて正の整数で上限以下', () {
    for (final s in build()) {
      expect(s.amount, greaterThan(0));
      expect(s.amount.toDouble(), lessThanOrEqualTo(kMaxAmount));
      // int で持っているので小数になりようがないが、型を変えたときに気付けるようにする。
      expect(s.amount.toDouble(), s.amount.toDouble().roundToDouble());
    }
  });

  test('外部キーになる ID は渡した値だけを使う', () {
    for (final s in build()) {
      expect(categoryIds.values, contains(s.categoryId));
      expect(memberIds, contains(s.memberId));
    }
  });

  test('直近 12 か月に収まり、当月は基準日を超えない', () {
    final seeds = build();
    final oldest = DateTime(2025, 10, 1);
    final limit = DateTime(2026, 9, 9); // 基準日の翌日 0 時（半開区間の右端）

    for (final s in seeds) {
      expect(s.spentAt.isBefore(oldest), isFalse, reason: '${s.spentAt} が古すぎる');
      expect(s.spentAt.isBefore(limit), isTrue, reason: '${s.spentAt} が未来');
    }

    // 昇順で返る。
    for (var i = 1; i < seeds.length; i++) {
      expect(seeds[i - 1].spentAt.isAfter(seeds[i].spentAt), isFalse);
    }
  });

  test('12 か月ぶんが 1 か月も欠けず、終わった月は 30 件前後になる', () {
    final byMonth = <String, int>{};
    for (final s in build()) {
      final key = '${s.spentAt.year}-${s.spentAt.month}';
      byMonth[key] = (byMonth[key] ?? 0) + 1;
    }

    expect(byMonth.length, 12);
    for (final entry in byMonth.entries) {
      if (entry.key == '2026-9') continue; // 当月は下のテストで見る
      expect(
        entry.value,
        inInclusiveRange(20, 40),
        reason: '${entry.key} が ${entry.value} 件',
      );
    }
  });

  test('当月は経過日数ぶんしか作らない', () {
    // 基準日は 9/8。満額を 8 日間に押し込むと、月初でも「先月並みに使った月」に
    // 見えてしまい、ホームの先月比が読めなくなる。
    final byMonth = <int, int>{};
    for (final s in build()) {
      byMonth[s.spentAt.month] = (byMonth[s.spentAt.month] ?? 0) + 1;
    }

    final current = byMonth[9]!;
    final previous = byMonth[8]!;
    expect(current, greaterThan(0));
    expect(current, lessThan(previous ~/ 2), reason: '当月が $current 件で減っていない');
  });

  test('家賃は毎月同じ人が払い、他の費目は 2 人に散る', () {
    final seeds = build();
    final rent = seeds.where((s) => s.categoryId == categoryIds['住居費']);

    expect(rent, isNotEmpty);
    expect(rent.every((s) => s.memberId == memberIds.first), isTrue);
    // 立替が片方に寄りきると割り勘の表示が確かめられない。
    expect(
      seeds.where((s) => s.memberId == memberIds[1]).length,
      greaterThan(0),
    );
  });

  test('娯楽費・衣服には単発の大きい出費が混ざる', () {
    // 月合計に振れが無いと、ホームの先月比がいつも横ばいになる。
    final seeds = build();
    final leisure = seeds.where((s) => s.categoryId == categoryIds['娯楽費']);

    expect(leisure.where((s) => s.amount > 9000), isNotEmpty);
  });

  test('同じ基準日とシードなら結果は毎回同じ', () {
    final a = build();
    final b = build();

    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].amount, b[i].amount);
      expect(a[i].spentAt, b[i].spentAt);
      expect(a[i].categoryId, b[i].categoryId);
      expect(a[i].memberId, b[i].memberId);
      expect(a[i].memo, b[i].memo);
    }
  });

  test('シードを変えると内容が変わる', () {
    final a = build();
    final b = build(seed: 1);

    final sumA = a.fold<int>(0, (v, s) => v + s.amount);
    final sumB = b.fold<int>(0, (v, s) => v + s.amount);
    expect(sumA, isNot(sumB));
  });

  test('メモは一部だけ付き、全件が同じにはならない', () {
    final seeds = build();
    final withMemo = seeds.where((s) => s.memo != null).length;

    expect(withMemo, greaterThan(0));
    expect(withMemo, lessThan(seeds.length));
  });

  test('知らないカテゴリ名は飛ばして落ちない', () {
    // ユーザーがカテゴリを削除・改名した端末を想定する。
    final seeds = buildSeedTransactions(
      now: now,
      categoryIdsByName: const {'食費': 42},
      memberIds: memberIds,
      months: 2,
    );

    expect(seeds, isNotEmpty);
    expect(seeds.every((s) => s.categoryId == 42), isTrue);
  });

  test('メンバーが 1 人でも動く', () {
    final seeds = buildSeedTransactions(
      now: now,
      categoryIdsByName: categoryIds,
      memberIds: const [7],
      months: 2,
    );

    expect(seeds, isNotEmpty);
    expect(seeds.every((s) => s.memberId == 7), isTrue);
  });

  test('メンバー 0 人と 0 か月は引数エラー', () {
    expect(
      () => buildSeedTransactions(
        now: now,
        categoryIdsByName: categoryIds,
        memberIds: const [],
      ),
      throwsArgumentError,
    );
    expect(
      () => buildSeedTransactions(
        now: now,
        categoryIdsByName: categoryIds,
        memberIds: memberIds,
        months: 0,
      ),
      throwsArgumentError,
    );
  });

  test('月の末日は閏年を含めて正しく求まる', () {
    // 日を選ぶ上限。ここを誤ると DateTime が静かに翌月へ繰り上げ（2/30 → 3/2）、
    // その月の件数が減って翌月が増える。生成結果からは「どの月ぶんとして
    // 作られたか」が分からず検出できないので、境界の計算を直接固定する。
    expect(lastDayOfMonth(2026, 2), 28);
    expect(lastDayOfMonth(2024, 2), 29); // 閏年
    expect(lastDayOfMonth(2000, 2), 29); // 400 年に 1 度の閏年
    expect(lastDayOfMonth(1900, 2), 28); // 100 年ごとの例外
    expect(lastDayOfMonth(2026, 4), 30);
    expect(lastDayOfMonth(2026, 12), 31);
    expect(lastDayOfMonth(2026, 1), 31);
  });

  test('生成した日付は月をまたがない', () {
    // 各月の件数が、その月に割り当てた件数と食い違わないことで見る。
    // 繰り上がりが起きると 2 月が減って 3 月が増える。
    final seeds = buildSeedTransactions(
      now: DateTime(2026, 3, 31),
      categoryIdsByName: categoryIds,
      memberIds: memberIds,
      months: 3,
    );

    final byMonth = <int, int>{};
    for (final s in seeds) {
      byMonth[s.spentAt.month] = (byMonth[s.spentAt.month] ?? 0) + 1;
    }

    // 1〜3 月の 3 か月ぶんだけが作られ、4 月以降へこぼれない。
    expect(byMonth.keys.toList()..sort(), [1, 2, 3]);
    // 各月は費目ごとの件数の合計（24〜36 件）に収まる。
    for (final entry in byMonth.entries) {
      expect(
        entry.value,
        inInclusiveRange(24, 36),
        reason: '${entry.key} 月が ${entry.value} 件',
      );
    }
  });
}
