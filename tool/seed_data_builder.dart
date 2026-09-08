/// 開発用のダミー取引を組み立てる純関数。
///
/// アプリ本体（`lib/`）からは参照されない開発専用のコードで、Flutter にも
/// drift にも依存しない。DB へ書き込む処理は `tool/seed_dev_data.dart` が持ち、
/// ここは「どんな取引をいくつ作るか」だけを決める。分けてあるのは、
/// 生成結果を DB なしでテストできるようにするため（`summary_calculator.dart` が
/// DB に触らないのと同じ方針）。
library;

import 'dart:math';

/// 生成した取引 1 件ぶんの素データ。
///
/// DB の型（drift の Companion）には依存しない。`amount` は `int` で持つ。
/// `transactions.amount` の列型は REAL だが CHECK が整数だけを通すため、
/// 生成側では最初から整数として扱い、投入時に `toDouble()` する。
class SeedTransaction {
  const SeedTransaction({
    required this.categoryId,
    required this.memberId,
    required this.amount,
    required this.spentAt,
    this.memo,
  });

  final int categoryId;
  final int memberId;

  /// 正の整数（円）。
  final int amount;

  /// 支出日時（ローカル時刻）。
  final DateTime spentAt;

  /// メモ。すべてに付けると不自然なので一部は null にする。
  final String? memo;
}

/// カテゴリごとの生成ルール。
class _CategorySpec {
  const _CategorySpec(
    this.name, {
    required this.minCount,
    required this.maxCount,
    required this.minAmount,
    required this.maxAmount,
    required this.memos,
    this.isFixedCost = false,
    this.seasonal = false,
    this.paidByFirstMember = false,
    this.allowSplurge = false,
  });

  final String name;
  final int minCount;
  final int maxCount;
  final int minAmount;
  final int maxAmount;
  final List<String> memos;

  /// 家賃・通信費のような固定費。引き落としらしく月の前半に寄せる。
  final bool isFixedCost;

  /// 冷暖房で夏冬に増える費目（光熱費）。
  final bool seasonal;

  /// 支払者を 1 人目に固定する費目。家賃のように毎月同じ人が払うもの。
  /// 立替が偏るので、割り勘・精算の表示を確かめるのに使う。
  final bool paidByFirstMember;

  /// 旅行・家電のような単発の大きい出費が混ざる費目。
  /// 月合計に振れを作り、ホームの先月比が動くようにする。
  final bool allowSplurge;
}

/// 既定カテゴリ 10 件に対応する生成ルール。
///
/// 合計は月あたり 28〜32 件、20 万円前後になるよう配分してある。
/// カテゴリ名は `lib/db/database.dart` の `_defaultCategories` と対応するが、
/// ID は呼び出し側が DB から引いた実 ID を渡す（ここに ID を直書きしない）。
const _specs = <_CategorySpec>[
  _CategorySpec(
    '食費',
    minCount: 11,
    maxCount: 13,
    minAmount: 300,
    maxAmount: 4500,
    memos: ['スーパー', 'コンビニ', 'ランチ', '外食', 'カフェ', 'パン屋', '弁当'],
  ),
  _CategorySpec(
    '日用品',
    minCount: 3,
    maxCount: 5,
    minAmount: 200,
    maxAmount: 3500,
    memos: ['ドラッグストア', '洗剤', 'ティッシュ', '生活雑貨', '文房具'],
  ),
  _CategorySpec(
    '交通費',
    minCount: 3,
    maxCount: 5,
    minAmount: 180,
    maxAmount: 1600,
    memos: ['電車', 'バス', 'タクシー', 'ICチャージ'],
  ),
  _CategorySpec(
    '光熱費',
    minCount: 2,
    maxCount: 2,
    minAmount: 3000,
    maxAmount: 9000,
    memos: ['電気代', 'ガス代', '水道代'],
    isFixedCost: true,
    seasonal: true,
  ),
  _CategorySpec(
    '通信費',
    minCount: 1,
    maxCount: 1,
    minAmount: 4200,
    maxAmount: 6000,
    memos: ['携帯', '光回線'],
    isFixedCost: true,
  ),
  _CategorySpec(
    '住居費',
    minCount: 1,
    maxCount: 1,
    minAmount: 78000,
    maxAmount: 78000,
    memos: ['家賃'],
    isFixedCost: true,
    paidByFirstMember: true,
  ),
  _CategorySpec(
    '医療費',
    minCount: 0,
    maxCount: 1,
    minAmount: 800,
    maxAmount: 6000,
    memos: ['病院', '薬局', '歯医者'],
  ),
  _CategorySpec(
    '娯楽費',
    minCount: 2,
    maxCount: 4,
    minAmount: 600,
    maxAmount: 9000,
    memos: ['映画', '書籍', 'サブスク', '旅行', 'ゲーム'],
    allowSplurge: true,
  ),
  _CategorySpec(
    '衣服',
    minCount: 0,
    maxCount: 2,
    minAmount: 1500,
    maxAmount: 12000,
    memos: ['シャツ', '靴', 'アウター', 'クリーニング'],
    allowSplurge: true,
  ),
  _CategorySpec(
    'その他',
    minCount: 1,
    maxCount: 2,
    minAmount: 500,
    maxAmount: 5000,
    memos: ['雑費', 'プレゼント', '手数料'],
  ),
];

/// 生成ルールを持つカテゴリ名の一覧。
///
/// 呼び出し側が「DB のカテゴリ名と一致しないので飛ばした」ことを知らせるために使う。
List<String> get seedCategoryNames => [for (final s in _specs) s.name];

/// 直近 [months] か月ぶんのダミー取引を組み立てる。
///
/// - [now] は基準日。**この関数は `DateTime.now()` を読まない**ので、
///   テストからは固定日を渡せる。
/// - [categoryIdsByName] はカテゴリ名から実 ID への対応。DB から引いた値を渡す。
///   ここに無い名前のカテゴリは生成をスキップするので、ユーザーがカテゴリを
///   削除・改名した端末でも落ちない。
/// - [memberIds] は支払者の候補。1 人でも動く（その 1 人に全件が付く）。
/// - [seed] を固定しているので、同じ [now] と [seed] なら結果は毎回同じになる。
///
/// 戻り値は `spentAt` の昇順。
List<SeedTransaction> buildSeedTransactions({
  required DateTime now,
  required Map<String, int> categoryIdsByName,
  required List<int> memberIds,
  int months = 12,
  int seed = 20260908,
}) {
  if (memberIds.isEmpty) {
    throw ArgumentError.value(memberIds, 'memberIds', 'メンバーが 1 人も渡されていない');
  }
  if (months < 1) {
    throw ArgumentError.value(months, 'months', '1 以上を指定する');
  }

  final random = Random(seed);
  final result = <SeedTransaction>[];

  // 基準月を含む直近 months か月。古い月から順に回す。
  for (var offset = months - 1; offset >= 0; offset--) {
    final monthStart = DateTime(now.year, now.month - offset, 1);
    final isCurrentMonth = offset == 0;
    final monthLastDay = lastDayOfMonth(monthStart.year, monthStart.month);
    // 当月は基準日までしか作らない（未来の取引を混ぜない）。
    final lastDay = isCurrentMonth ? now.day : monthLastDay;

    for (final spec in _specs) {
      final categoryId = categoryIdsByName[spec.name];
      if (categoryId == null) continue;

      final count =
          spec.minCount + random.nextInt(spec.maxCount - spec.minCount + 1);
      for (var i = 0; i < count; i++) {
        final day =
            spec.isFixedCost
                // 固定費は引き落とし日らしく月の前半に寄せる。
                ? 1 + random.nextInt(min(10, monthLastDay))
                : 1 + random.nextInt(monthLastDay);
        final spentAt = DateTime(
          monthStart.year,
          monthStart.month,
          day,
          8 + random.nextInt(14),
          random.nextInt(60),
        );
        final transaction = SeedTransaction(
          categoryId: categoryId,
          memberId: _pickMember(spec, memberIds, random),
          amount: _pickAmount(spec, monthStart.month, random),
          spentAt: spentAt,
          memo: _pickMemo(spec, random),
        );

        // 日付は必ず月全体から選び、当月のまだ来ていない日ぶんは捨てる。
        // こうすると当月の件数が経過日数ぶんだけ自然に減る（満額を数日に
        // 押し込むと、月初でも「先月並みに使った月」に見えてしまう）。
        // 捨てるのは値を作り終えてからにして、乱数の消費量を月によらず
        // 一定に保つ（途中で continue すると以降の生成がずれる）。
        if (day > lastDay) continue;
        result.add(transaction);
      }
    }
  }

  result.sort((a, b) => a.spentAt.compareTo(b.spentAt));
  return result;
}

/// [year] 年 [month] 月の末日（28〜31）。
///
/// 生成する日をこの範囲に収めるための境界。ここを誤ると `DateTime` が
/// 静かに翌月へ繰り上げるため（2 月 30 日 → 3 月 2 日）、その月の件数が減って
/// 翌月が増える。例外も出ず、生成結果を見ても意図した月が分からないので、
/// **境界の計算そのものをテストで固定する**。
///
/// 翌月 0 日は「その月の末日」になる、という `DateTime` の正規化を使う。
int lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// 支払者を選ぶ。家賃だけ 1 人目に固定し、それ以外はおよそ 55:45 で振り分ける。
///
/// 乱数は常に引く。引くかどうかを条件で変えると、費目の構成を変えたときに
/// 他の費目の結果までずれてしまう。
int _pickMember(_CategorySpec spec, List<int> memberIds, Random random) {
  final pick = random.nextInt(100) < 55 ? 0 : 1;
  if (spec.paidByFirstMember || memberIds.length == 1) return memberIds.first;
  return memberIds[pick];
}

/// 金額を選ぶ。光熱費は冷暖房ぶんを季節で上乗せし、
/// 娯楽費・衣服にはたまに旅行・家電のような単発の大きい出費を混ぜる。
int _pickAmount(_CategorySpec spec, int month, Random random) {
  var base =
      spec.minAmount + random.nextInt(spec.maxAmount - spec.minAmount + 1);

  // 乱数は費目によらず必ず引く（引かないと以降の生成がずれる）。
  final splurge = random.nextInt(100) < 12;
  final splurgeFactor = 3 + random.nextInt(4);
  if (spec.allowSplurge && splurge) base *= splurgeFactor;

  if (!spec.seasonal) return base;

  final factor = switch (month) {
    12 || 1 || 2 => 1.6, // 暖房
    7 || 8 => 1.3, // 冷房
    _ => 1.0,
  };
  return (base * factor).round();
}

/// メモを選ぶ。6 割だけ付けて、残りは null のままにする
/// （`memo` が NULL 可であることを実データでも再現するため）。
String? _pickMemo(_CategorySpec spec, Random random) {
  if (random.nextInt(10) >= 6) return null;
  return spec.memos[random.nextInt(spec.memos.length)];
}
