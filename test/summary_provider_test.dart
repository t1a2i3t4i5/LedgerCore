import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';

/// 集計画面の期間モードを、画面を組み立てずに見るテスト。
///
/// **`SummaryProvider` は集計タブと割り勘タブで 1 インスタンスを共有する**
/// （`main.dart` の MultiProvider）。集計タブのモードを理由に割り勘のデータを
/// 落とすと、割り勘タブを開いた人に「データがありません」が出る。
/// 画面テストではタブを跨がないと気付けないので、ここで塞ぐ。
void main() {
  late AppDatabase db;
  late SummaryProvider provider;

  // 表示月を実時刻から切り離す。「今月」にテストデータを置かない
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = SummaryProvider(db, clock: () => fixedNow);
  });
  tearDown(() async => db.close());

  Future<void> seed(DateTime spentAt, double amount,
      {int categoryIndex = 0}) async {
    final categories = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: categories[categoryIndex].id,
        amount: amount,
        spentAt: spentAt,
      ),
    );
  }

  /// 2025 年に 1 件、2026 年に 2 件。年ごと・月ごとに金額を変えて
  /// 「どの期間を読んだか」を金額で判別できるようにする
  Future<void> seedThreeYears() async {
    await seed(DateTime(2025, 3, 5), 250);
    await seed(DateTime(2026, 3, 5), 300, categoryIndex: 1);
    await seed(DateTime(2026, 7, 5), 700);
  }

  group('既定の状態', () {
    test('月モードで始まり、年次データは持たない', () async {
      await seedThreeYears();

      await provider.fetch();

      expect(provider.period, SummaryPeriod.month);
      expect(provider.yearly, isNull);
      expect(provider.allYears, isEmpty);
      // clock の月（2026/7）の合計
      expect(provider.summary!.total, 700);
    });
  });

  group('年モード', () {
    test('12 か月ぶんを取り、取引の無い月は 0 になる', () async {
      await seedThreeYears();

      await provider.setPeriod(SummaryPeriod.year);

      final byMonth = provider.yearly!.byMonth;
      expect(byMonth.length, 12);
      expect(byMonth.map((p) => p.month), List.generate(12, (i) => i + 1));
      expect(byMonth[2].total, 300, reason: '3 月');
      expect(byMonth[6].total, 700, reason: '7 月');
      expect(byMonth[0].total, 0, reason: '取引の無い 1 月');
      // 2025 年の 250 は混ざらない
      expect(provider.yearly!.total, 1000);
    });

    test('カテゴリ別はその年ぶんを合算する', () async {
      await seedThreeYears();

      await provider.setPeriod(SummaryPeriod.year);

      final byCategory = provider.yearly!.byCategory;
      expect(byCategory.length, 2);
      // 合計金額の降順
      expect(byCategory.first.total, 700);
      expect(byCategory.last.total, 300);
    });

    test('年を送ると送った先の年を読み直す', () async {
      await seedThreeYears();
      await provider.setPeriod(SummaryPeriod.year);

      await provider.changeYear(-1);

      expect(provider.yearAxis, 2025);
      expect(provider.yearly!.year, 2025);
      expect(provider.yearly!.total, 250);
    });

    // 月モードで別の年へ移ってから年モードへ入ると、その年が出る。
    // 前に年モードで見ていた年を覚えていると、今見ている月と無関係な年が出る
    test('年モードに入ると年の軸を表示月の年に合わせる', () async {
      await seedThreeYears();
      await provider.setPeriod(SummaryPeriod.year);
      await provider.changeYear(-1);
      expect(provider.yearAxis, 2025);

      await provider.setPeriod(SummaryPeriod.month);
      await provider.goToMonth(2026, 3);
      await provider.setPeriod(SummaryPeriod.year);

      expect(provider.yearAxis, 2026);
      expect(provider.yearly!.year, 2026);
    });
  });

  group('全期間モード', () {
    // 受け入れ条件「取引のある年だけが昇順に並ぶ」
    test('取引のある年だけを昇順で持つ', () async {
      await seedThreeYears();

      await provider.setPeriod(SummaryPeriod.all);

      expect(provider.allYears.map((p) => p.year), [2025, 2026]);
      expect(provider.allYears.map((p) => p.total), [250, 1000]);
      // 年別の点なので month は持たない
      expect(provider.allYears.every((p) => p.month == null), isTrue);
    });
  });

  group('割り勘タブとの共有', () {
    // このテストがこのファイルの主目的。SummaryProvider は集計タブと割り勘タブで
    // 1 インスタンスしかないので、集計側の操作が割り勘側の表示期間を動かさない
    // ことをここで押さえる。
    //
    // **isNotNull だけでは足りない。** モードで取得を分岐させる改変のうち
    // 「前の値が残る」形は、存在確認では素通りする（初回 fetch の残骸が
    // そのまま残るため）。年月と金額を値で見る。
    test('どのモードでも月次サマリーと割り勘を 2026/7 のまま持ち続ける', () async {
      await seedThreeYears();
      // 画面は initState で fetch を呼ぶ。setPeriod は同じモードなら
      // 早期 return するので、初回の取得はここで済ませておく
      await provider.fetch();

      for (final period in SummaryPeriod.values) {
        await provider.setPeriod(period);

        expect(provider.summary, isNotNull, reason: '$period で月次が落ちた');
        expect(provider.split, isNotNull, reason: '$period で割り勘が落ちた');
        expect(provider.summary!.year, 2026, reason: '$period で月次の年が動いた');
        expect(provider.summary!.month, 7, reason: '$period で月次の月が動いた');
        expect(provider.summary!.total, 700, reason: '$period で月次の額が変わった');
        expect(provider.split!.year, 2026, reason: '$period で割り勘の年が動いた');
        expect(provider.split!.month, 7, reason: '$period で割り勘の月が動いた');
        expect(provider.split!.total, 700, reason: '$period で割り勘の額が変わった');
      }
    });

    // 実測で踏んだ事故そのもの。年を送ったら割り勘タブが 2026年7月 / ¥700 から
    // 2025年7月 / ¥250 に化けた（ユーザーは割り勘タブで何も操作していない）。
    // 「月の数値さえ保てば無事」ではなく、年を動かした時点で対象期間が変わる
    test('年を送っても割り勘と月次は表示月のまま動かない', () async {
      await seedThreeYears();
      await provider.setPeriod(SummaryPeriod.year);

      await provider.changeYear(-1);

      expect(provider.yearAxis, 2025, reason: '年の軸は動くべき');
      expect(provider.split!.year, 2026, reason: '割り勘の年を巻き込んでいる');
      expect(provider.split!.total, 700);
      expect(provider.summary!.year, 2026);
      expect(provider.summary!.total, 700);
    });

    test('「今年に戻る」でも割り勘と月次は動かない', () async {
      await seedThreeYears();
      // 表示月を今月から離しておく。ここが動かないことを見たい
      await provider.goToMonth(2026, 3);
      await provider.setPeriod(SummaryPeriod.year);
      await provider.changeYear(-2);
      expect(provider.isCurrentYear, isFalse);

      await provider.goToCurrentYear();

      expect(provider.yearAxis, 2026);
      expect(provider.isCurrentYear, isTrue);
      // goToCurrentMonth と取り違えると、ここが 7 月に戻る
      expect(provider.month, 3, reason: '表示月を今月に戻してはいけない');
      expect(provider.split!.month, 3);
    });
  });

  group('モードの切り替え', () {
    // 残すと「年を送る → 月モードへ戻す → また年モードへ」の途中で
    // 前の年のグラフを一瞬描く経路ができる
    test('モードを外れた期間のデータは捨てる', () async {
      await seedThreeYears();

      await provider.setPeriod(SummaryPeriod.year);
      expect(provider.yearly, isNotNull);

      await provider.setPeriod(SummaryPeriod.all);
      expect(provider.yearly, isNull, reason: '年モードを離れても年次が残っている');
      expect(provider.allYears, isNotEmpty);

      await provider.setPeriod(SummaryPeriod.month);
      expect(provider.allYears, isEmpty, reason: '全期間を離れても年別が残っている');
    });

    test('同じモードを選び直しても通知も再取得もしない', () async {
      await seedThreeYears();
      await provider.fetch();

      var notifyCount = 0;
      provider.addListener(() => notifyCount++);
      await provider.setPeriod(SummaryPeriod.month);

      expect(notifyCount, 0);
    });

    test('モードを変えると通知が走る', () async {
      await seedThreeYears();
      await provider.fetch();

      var notifyCount = 0;
      provider.addListener(() => notifyCount++);
      await provider.setPeriod(SummaryPeriod.year);

      // 切り替え直後の 1 回 + fetch の開始・終了で 2 回
      expect(notifyCount, 3);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    });
  });

  group('取引が 1 件も無いとき', () {
    // 受け入れ条件「取引が 1 件もない状態でも例外なく表示できる」
    test('どのモードでもエラーにならず空の結果を返す', () async {
      await provider.fetch();

      for (final period in SummaryPeriod.values) {
        await provider.setPeriod(period);

        expect(provider.error, isNull, reason: '$period でエラーになった');
        expect(provider.summary!.total, 0);
        expect(provider.summary!.byCategory, isEmpty);
      }

      await provider.setPeriod(SummaryPeriod.year);
      // 取引ゼロでも 12 か月ぶんの枠は返る（グラフの X 軸を欠けさせない）
      expect(provider.yearly!.byMonth.length, 12);
      expect(provider.yearly!.total, 0);

      await provider.setPeriod(SummaryPeriod.all);
      // 取引のある年が 1 つも無いので空
      expect(provider.allYears, isEmpty);
    });
  });
}
