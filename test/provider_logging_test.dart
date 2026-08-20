import 'dart:convert';

import 'package:drift/drift.dart' show InvalidDataException;
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

import 'matchers.dart';

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
      provider = TransactionProvider(db, logger: logger)..setYearMonth(2026, 7);
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
        throwsAmountCheckViolation,
      );
      await logger.flush();

      final entry = entryOf('transaction.create');
      expect(entry['lv'], 'error');
      // **何か入っていること（isNotNull）では守れない。** 失敗の理由が
      // 定数文字列にすり替わっても通ってしまう
      expect(entry['error'], contains('CHECK constraint failed'));
      // 失敗したのに info の行まで出ていないこと
      expect(ops().where((o) => o == 'transaction.create'), hasLength(1));
    });

    test('保存に失敗してもメモ本文は error 経由で漏れない', () async {
      // detail から本文を外しても、DB の例外はバインド値を文字列に並べるので
      // **同じ行の error にメモ本文が丸ごと載っていた**（detail の
      // memoLength:6 と本文が並ぶ）。ログファイルは端末外へ持ち出されうる
      await expectLater(
        provider.create(await anInput(amount: 0, memo: 'ひみつの通院')),
        throwsAmountCheckViolation,
      );
      await logger.flush();

      expect(allText(), isNot(contains('ひみつ')));
      expect(allText(), isNot(contains('通院')));
      // 長さは今までどおり残る。伏せたのは値だけ
      expect(detailOf('transaction.create')['memoLength'], 6);
      // 失敗の理由とどの文で落ちたかは残す（伏せすぎの検出）
      final error = entryOf('transaction.create')['error'] as String;
      expect(error, contains('CHECK constraint failed'));
      expect(error, contains('INSERT INTO "transactions"'));
    });

    test('更新の失敗でもメモ本文は漏れない', () async {
      await provider.create(await anInput(amount: 1500));
      final id = provider.transactions.single.id;

      await expectLater(
        provider.update(id, await anInput(amount: 0, memo: 'ひみつの通院')),
        throwsAmountCheckViolation,
      );
      await logger.flush();

      expect(allText(), isNot(contains('ひみつ')));
      expect(
        entryOf('transaction.update')['error'],
        contains('CHECK constraint failed'),
      );
    });

    test('更新の失敗も error として残り、例外は届く', () async {
      await provider.create(await anInput(amount: 1500));
      final id = provider.transactions.single.id;

      await expectLater(
        provider.update(id, await anInput(amount: 0)),
        throwsAmountCheckViolation,
      );
      await logger.flush();

      final updates =
          entries().where((e) => e['op'] == 'transaction.update').toList();
      expect(updates, hasLength(1));
      expect(updates.single['lv'], 'error');
      // 失敗した更新が一覧に反映されていないこと
      expect(provider.transactions.single.amount, 1500.0);
    });

    test('削除の失敗も error として残り、例外は届く', () async {
      await provider.create(await anInput(amount: 1500));
      final id = provider.transactions.single.id;
      // 取引を参照する子テーブルが無いので、削除が落ちる経路は制約では作れない。
      // DB 側から拒否させて、ログのために足した try が握り潰していないか見る
      await db.customStatement(
        "CREATE TRIGGER no_delete BEFORE DELETE ON transactions "
        "BEGIN SELECT RAISE(ABORT, '削除できません'); END;",
      );

      await expectLater(provider.delete(id), throwsA(isA<Exception>()));
      await logger.flush();

      final entry = entryOf('transaction.delete');
      expect(entry['lv'], 'error');
      expect(entry['error'], contains('削除できません'));
      // 失敗した削除が一覧から消えていないこと
      expect(provider.transactions, hasLength(1));
    });

    test('並び替えと絞り込みが残る', () async {
      provider.setSort(TransactionSortField.amount, SortOrder.asc);
      await logger.flush();

      expect(detailOf('transaction.sort'), {'field': 'amount', 'order': 'asc'});
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

    test('支払者と金額での絞り込みも軸ごとに残る', () async {
      // memberIds を非空で、hasAmountRange を true で試す唯一のケース。
      // 片側だけだと categoryIds とのコピペ違いや、activeFilterCount と
      // 食い違う `&&` 判定が入っても気づけない
      provider.setFilters(memberIds: {2}, minAmount: 1000);
      await logger.flush();

      final detail = detailOf('transaction.filter');
      expect(detail['memberIds'], [2]);
      expect(detail['hasAmountRange'], isTrue);
      // 検索語なしなら false。true 固定になっていないこと
      expect(detail['hasMemoQuery'], isFalse);
      // 金額の下限だけでも「絞っている」と数える activeFilterCount と揃うこと
      expect(detail['activeCount'], 2);
      // 絞っていない軸のキーは出ない
      expect(detail.containsKey('categoryIds'), isFalse);
    });

    test('金額の上限だけでも hasAmountRange は true', () async {
      provider.setFilters(maxAmount: 5000);
      await logger.flush();

      final detail = detailOf('transaction.filter');
      expect(detail['hasAmountRange'], isTrue);
      expect(detail['activeCount'], 1);
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
      expect(
        entryOf('transaction.filter.reset').containsKey('detail'),
        isFalse,
      );
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

    test('追加の失敗は error で残り、例外も届く', () async {
      // Categories.name は withLength(max: 50) で drift のクライアント側検証が
      // 効く。categories_screen.dart の TextField に maxLength が無いので、
      // 51 文字を入力して「保存」を押せば実際にこの経路へ入る。
      // **rethrow が落ちると画面の catch に届かず、追加できていないのに
      // 「保存失敗」の SnackBar も出ない**
      await expectLater(
        provider.create('あ' * 51),
        throwsA(isA<InvalidDataException>()),
      );
      await logger.flush();

      final entry = entryOf('category.create');
      expect(entry['lv'], 'error');
      // 失敗したのに info の行まで出ていないこと
      expect(ops().where((o) => o == 'category.create'), hasLength(1));
    });

    test('改名の失敗も error で残り、例外も届く', () async {
      await provider.create('サブスク代');
      final added = provider.categories.firstWhere((c) => c.name == 'サブスク代');

      await expectLater(
        provider.update(added.id, 'あ' * 51),
        throwsA(isA<InvalidDataException>()),
      );
      await logger.flush();

      final updates =
          entries().where((e) => e['op'] == 'category.update').toList();
      expect(updates, hasLength(1));
      expect(updates.single['lv'], 'error');
      // 失敗した改名が一覧に反映されていないこと
      expect(
        provider.categories.firstWhere((c) => c.id == added.id).name,
        'サブスク代',
      );
    });

    test('取引が紐づくカテゴリの削除は error で残り、例外も届く', () async {
      final transactions = TransactionProvider(db)..setYearMonth(2026, 7);
      await transactions.create(await anInput());
      final used = (await db.getCategories()).first;

      await expectLater(provider.delete(used.id), throwsForeignKeyViolation);
      await logger.flush();

      final entry = entryOf('category.delete');
      expect(entry['lv'], 'error');
      // 「なぜ消せなかったか」が残る数少ない経路なので、理由まで見る
      expect(entry['error'], contains('FOREIGN KEY constraint failed'));
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

    test('追加の失敗は error で残り、例外も届く', () async {
      // Members.name も withLength(max: 50)。カテゴリと同じ経路
      await expectLater(
        provider.addMember('あ' * 51),
        throwsA(isA<InvalidDataException>()),
      );
      await logger.flush();

      expect(entryOf('member.create')['lv'], 'error');
      expect(ops().where((o) => o == 'member.create'), hasLength(1));
    });

    test('改名の失敗も error で残り、例外も届く', () async {
      await provider.addMember('同居人');
      final added = provider.members.firstWhere((m) => m.name == '同居人');

      await expectLater(
        provider.updateMember(added.id, 'あ' * 51),
        throwsA(isA<InvalidDataException>()),
      );
      await logger.flush();

      final updates =
          entries().where((e) => e['op'] == 'member.update').toList();
      expect(updates, hasLength(1));
      expect(updates.single['lv'], 'error');
      // 失敗した改名が一覧に反映されていないこと
      expect(provider.members.firstWhere((m) => m.id == added.id).name, '同居人');
    });

    test('取引の支払者になっているメンバーの削除は error で残る', () async {
      final transactions = TransactionProvider(db)..setYearMonth(2026, 7);
      await transactions.create(await anInput());
      final used = (await db.getMembers()).first;

      await expectLater(
        provider.deleteMember(used.id),
        throwsForeignKeyViolation,
      );
      await logger.flush();

      final entry = entryOf('member.delete');
      expect(entry['lv'], 'error');
      expect(entry['error'], contains('FOREIGN KEY constraint failed'));
    });
  });

  group('読み出しの失敗', () {
    // fetch() は例外を握って _error に載せる（画面が「読み込めません」を出す）。
    // **握るぶん、どこにも記録が残らないと後から追えない**ので、
    // debugPrint を logger.error に置き換えたこの 4 経路を実際に通す。
    // DB を閉じてから読むと、drift が閉じた DB への操作を拒否する。
    // **閉じる前に 1 度読んで DB を開かせておく。** forTesting は遅延接続で、
    // 一度も開いていない DB は close() しても開き直せてしまい失敗しない
    Future<void> closeAfterOpening() async {
      await db.getCategories();
      await db.close();
    }

    test('取引の読み出し失敗が表示月つきで残る', () async {
      final provider = TransactionProvider(db, logger: logger)
        ..setYearMonth(2026, 7);
      await closeAfterOpening();

      await provider.fetch();
      await logger.flush();

      final entry = entryOf('transaction.fetch');
      expect(entry['lv'], 'error');
      expect(entry['detail'], {'year': 2026, 'month': 7});
    });

    test('集計の読み出し失敗はモードと年軸まで残る', () async {
      final provider = SummaryProvider(db, logger: logger)
        ..setYearMonth(2026, 7);
      await closeAfterOpening();

      await provider.fetch();
      await logger.flush();

      final entry = entryOf('summary.fetch');
      expect(entry['lv'], 'error');
      expect(detailOf('summary.fetch'), {
        'year': 2026,
        'month': 7,
        'period': 'month',
        'yearAxis': 2026,
      });
    });

    test('カテゴリの読み出し失敗が残る', () async {
      final provider = CategoryProvider(db, logger: logger);
      await closeAfterOpening();

      await provider.fetch();
      await logger.flush();

      expect(entryOf('category.fetch')['lv'], 'error');
    });

    test('メンバーの読み出し失敗が残る', () async {
      final provider = MemberProvider(db, logger: logger);
      await closeAfterOpening();

      await provider.fetchMembers();
      await logger.flush();

      expect(entryOf('member.fetch')['lv'], 'error');
    });
  });

  group('ロガーを渡さない既定', () {
    test('Provider は logger 無しでも今までどおり動く', () async {
      // **ここで sink を見ても意味が無い。** この Provider に sink は
      // 繋がっていないので、`expect(sink.lines, isEmpty)` は実装が何をしても
      // 真になる（既定がファイル書き込みに変わっても緑のまま通る）。
      // 確かめられるのは「logger を省いても操作が今までどおり通ること」だけ
      final provider = TransactionProvider(db)..setYearMonth(2026, 7);
      await provider.create(await anInput());

      expect(provider.transactions, hasLength(1));
    });
  });
}
