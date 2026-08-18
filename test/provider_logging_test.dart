import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/logging/log_sink.dart';
import 'package:ledger_app/logging/operation_logger.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';

/// Provider の操作がログにどう出るかを確かめる。
///
/// ログ層そのものの検証は `test/logging/` にあるので、ここでは
/// **どの操作がどの op でどんな detail を残すか**と、
/// **失敗しても例外が画面まで届くか**（rethrow）に絞る。
void main() {
  late AppDatabase db;
  late MemoryLogSink sink;
  late OperationLogger logger;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sink = MemoryLogSink();
    logger = OperationLogger(sink, clock: () => DateTime(2026, 8, 17, 12));
  });
  tearDown(() async => db.close());

  List<Map<String, Object?>> entries() =>
      sink.lines.map((l) => jsonDecode(l) as Map<String, Object?>).toList();

  List<String> ops() => entries().map((e) => e['op'] as String).toList();

  Map<String, Object?> entryOf(String op) =>
      entries().firstWhere((e) => e['op'] == op);

  Map<String, Object?> detailOf(String op) =>
      entryOf(op)['detail'] as Map<String, Object?>;

  /// ログに書かれた全文。機微な文字列が「どこにも」出ていないことを見るのに使う
  String allText() => sink.lines.join('\n');

  Future<TransactionInput> anInput({
    double amount = 1200,
    String? memo,
    DateTime? spentAt,
  }) async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    return TransactionInput(
      memberId: members.first.id,
      categoryId: cats.first.id,
      amount: amount,
      spentAt: spentAt ?? DateTime(2026, 7, 10),
      memo: memo,
    );
  }

  group('取引', () {
    late TransactionProvider provider;

    setUp(() {
      provider = TransactionProvider(db, logger: logger)
        ..setYearMonth(2026, 7);
    });

    test('追加が info で残る', () async {
      await provider.create(await anInput(memo: '病院の領収書'));
      await logger.flush();

      final entry = entryOf('transaction.create');
      expect(entry['lv'], 'info');
      expect(entry['ts'], '2026-08-17T12:00:00.000');

      final detail = detailOf('transaction.create');
      expect(detail['amount'], 1200.0);
      expect(detail['spentAt'], '2026-07-10T00:00:00.000');
      // insertTransaction は採番された id を返さないので id は載らない
      expect(detail.containsKey('id'), isFalse);
    });

    test('メモは本文を残さず長さだけ残す', () async {
      // 家計簿のメモは機微になりうる一方、ログファイルは端末外へ持ち出されうる
      await provider.create(await anInput(memo: 'ひみつの通院'));
      await logger.flush();

      expect(detailOf('transaction.create')['memoLength'], 6);
      expect(allText(), isNot(contains('ひみつ')));
      expect(allText(), isNot(contains('通院')));
    });

    test('メモが無い取引は memoLength のキーごと出ない', () async {
      await provider.create(await anInput());
      await logger.flush();

      expect(detailOf('transaction.create').containsKey('memoLength'), isFalse);
    });

    test('更新と削除は id つきで残る', () async {
      await provider.create(await anInput(amount: 1500));
      final id = provider.transactions.single.id;

      await provider.update(id, await anInput(amount: 2500));
      await provider.delete(id);
      await logger.flush();

      expect(
        ops(),
        containsAllInOrder([
          'transaction.create',
          'transaction.update',
          'transaction.delete',
        ]),
      );
      expect(detailOf('transaction.update')['id'], id);
      expect(detailOf('transaction.update')['amount'], 2500.0);
      expect(detailOf('transaction.delete'), {'id': id});
    });

    test('保存に失敗すると error が残り、例外は呼び出し元まで届く', () async {
      // 金額 0 は DB の CHECK 制約に弾かれる。
      // **例外がここで止まると画面の SnackBar が出なくなる**ので、
      // ログのために足した try が握り潰していないことを見る
      await expectLater(
        provider.create(await anInput(amount: 0)),
        throwsA(anything),
      );
      await logger.flush();

      final entry = entryOf('transaction.create');
      expect(entry['lv'], 'error');
      expect(entry['error'], isNotNull);
      // 失敗したのに info の行まで出ていないこと
      expect(ops().where((o) => o == 'transaction.create'), hasLength(1));
    });

    test('更新の失敗も error として残り、例外は届く', () async {
      await provider.create(await anInput(amount: 1500));
      final id = provider.transactions.single.id;

      await expectLater(
        provider.update(id, await anInput(amount: 0)),
        throwsA(anything),
      );
      await logger.flush();

      final updates =
          entries().where((e) => e['op'] == 'transaction.update').toList();
      expect(updates, hasLength(1));
      expect(updates.single['lv'], 'error');
      // 失敗した更新が一覧に反映されていないこと
      expect(provider.transactions.single.amount, 1500.0);
    });

    test('並び替えと絞り込みが残る', () async {
      provider.setSort(TransactionSortField.amount, SortOrder.asc);
      await logger.flush();

      expect(detailOf('transaction.sort'), {
        'field': 'amount',
        'order': 'asc',
      });
    });

    test('絞り込みは検索語そのものを残さない', () async {
      provider.setFilters(categoryIds: {3, 1}, memoQuery: 'ひみつ');
      await logger.flush();

      final detail = detailOf('transaction.filter');
      expect(detail['activeCount'], 2);
      expect(detail['categoryIds'], [3, 1]);
      expect(detail['hasMemoQuery'], isTrue);
      expect(detail['hasAmountRange'], isFalse);
      expect(allText(), isNot(contains('ひみつ')));
    });

    test('絞り込んでいない軸はキーごと出ない', () async {
      provider.setFilters(memoQuery: 'x');
      await logger.flush();

      final detail = detailOf('transaction.filter');
      expect(detail.containsKey('categoryIds'), isFalse);
      expect(detail.containsKey('memberIds'), isFalse);
    });

    test('絞り込みの解除が残る', () async {
      provider.resetFilters();
      await logger.flush();

      expect(ops(), contains('transaction.filter.reset'));
      expect(entryOf('transaction.filter.reset').containsKey('detail'), isFalse);
    });
  });

  group('表示月の移動', () {
    test('矢印での月送りは via:arrow', () async {
      final provider = TransactionProvider(db, logger: logger)
        ..setYearMonth(2026, 7);

      await provider.changeMonth(-1);
      await logger.flush();

      expect(detailOf('month.change'), {
        'from': '2026-07',
        'to': '2026-06',
        'via': 'arrow',
      });
    });

    test('年をまたぐ月送りも正しい年月で残る', () async {
      final provider = TransactionProvider(db, logger: logger)
        ..setYearMonth(2026, 12);

      await provider.changeMonth(1);
      await logger.flush();

      expect(detailOf('month.change')['to'], '2027-01');
    });

    test('今月へ戻る操作は via:current', () async {
      final provider = TransactionProvider(
        db,
        clock: () => DateTime(2026, 8, 17),
        logger: logger,
      )..setYearMonth(2026, 3);

      await provider.goToCurrentMonth();
      await logger.flush();

      expect(detailOf('month.change'), {
        'from': '2026-03',
        'to': '2026-08',
        'via': 'current',
      });
    });

    test('月ジャンプは丸めた後の年月を残す', () async {
      // setYearMonth は 13 月を翌年 1 月へ正規化する。引数をそのまま書くと
      // 実際の表示は 2027-01 なのにログだけ 2026-13 になる
      final provider = TransactionProvider(db, logger: logger)
        ..setYearMonth(2026, 7);

      await provider.goToMonth(2026, 13);
      await logger.flush();

      expect(detailOf('month.change'), {
        'from': '2026-07',
        'to': '2027-01',
        'via': 'jump',
      });
    });
  });

  group('集計', () {
    late SummaryProvider provider;

    setUp(() {
      provider = SummaryProvider(
        db,
        clock: () => DateTime(2026, 8, 17),
        logger: logger,
      );
    });

    test('期間モードの切り替えが残る', () async {
      await provider.setPeriod(SummaryPeriod.year);
      await logger.flush();

      expect(detailOf('summary.period'), {'from': 'month', 'to': 'year'});
    });

    test('同じモードを選び直しても残さない', () async {
      await provider.setPeriod(SummaryPeriod.month);
      await logger.flush();

      expect(ops(), isNot(contains('summary.period')));
    });

    test('年送りは summary.year で、表示月は動かさない', () async {
      // 年の軸と表示月は独立している（同じインスタンスを割り勘タブが共有する）。
      // month.change が出るなら表示月ごと動いている
      await provider.changeYear(-1);
      await logger.flush();

      expect(detailOf('summary.year'), {'from': 2026, 'to': 2025});
      expect(ops(), isNot(contains('month.change')));
    });

    test('今年へ戻す操作も summary.year で残る', () async {
      await provider.changeYear(-3);
      await provider.goToCurrentYear();
      await logger.flush();

      final years = entries().where((e) => e['op'] == 'summary.year').toList();
      expect(years, hasLength(2));
      expect(years.last['detail'], {'from': 2023, 'to': 2026});
    });
  });

  group('カテゴリ', () {
    late CategoryProvider provider;

    setUp(() => provider = CategoryProvider(db, logger: logger));

    test('追加・更新・削除が名前つきで残る', () async {
      await provider.create('サブスク代');
      final added = provider.categories.firstWhere((c) => c.name == 'サブスク代');

      await provider.update(added.id, '定期購読費');
      await provider.delete(added.id);
      await logger.flush();

      // カテゴリ名は画面に常時出ているラベルなので、取引のメモと違って載せる
      expect(detailOf('category.create'), {'name': 'サブスク代'});
      expect(detailOf('category.update'), {'id': added.id, 'name': '定期購読費'});
      expect(detailOf('category.delete'), {'id': added.id});
    });

    test('取引が紐づくカテゴリの削除は error で残り、例外も届く', () async {
      final transactions = TransactionProvider(db)..setYearMonth(2026, 7);
      await transactions.create(await anInput());
      final used = (await db.getCategories()).first;

      await expectLater(provider.delete(used.id), throwsA(anything));
      await logger.flush();

      final entry = entryOf('category.delete');
      expect(entry['lv'], 'error');
      expect(entry['error'], isNotNull);
    });
  });

  group('メンバー', () {
    late MemberProvider provider;

    setUp(() => provider = MemberProvider(db, logger: logger));

    test('op はメソッド名ではなく member.create に揃える', () async {
      await provider.addMember('同居人');
      await logger.flush();

      expect(ops(), contains('member.create'));
      expect(detailOf('member.create'), {'name': '同居人'});
    });

    test('更新と削除が id つきで残る', () async {
      await provider.addMember('同居人');
      final added = provider.members.firstWhere((m) => m.name == '同居人');

      await provider.updateMember(added.id, '配偶者');
      await provider.deleteMember(added.id);
      await logger.flush();

      expect(detailOf('member.update'), {'id': added.id, 'name': '配偶者'});
      expect(detailOf('member.delete'), {'id': added.id});
    });

    test('取引の支払者になっているメンバーの削除は error で残る', () async {
      final transactions = TransactionProvider(db)..setYearMonth(2026, 7);
      await transactions.create(await anInput());
      final used = (await db.getMembers()).first;

      await expectLater(provider.deleteMember(used.id), throwsA(anything));
      await logger.flush();

      expect(entryOf('member.delete')['lv'], 'error');
    });
  });

  group('ロガーを渡さない既定', () {
    test('Provider は logger 無しでも今までどおり動く', () async {
      final provider = TransactionProvider(db)..setYearMonth(2026, 7);
      await provider.create(await anInput());

      expect(provider.transactions, hasLength(1));
      expect(sink.lines, isEmpty);
    });
  });
}
