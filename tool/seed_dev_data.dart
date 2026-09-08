/// 開発用のダミー取引を端末（シミュレータ）の DB へ投入するスクリプト。
///
/// **アプリには含まれない開発専用のコード**で、`lib/` からは参照されない。
/// 画面の見た目・集計・割り勘・フィルターを確認するときに、手入力の代わりに使う。
///
/// ## 使い方
///
/// 通常は `tool/seed_dev_data.sh` から呼ぶ（DB のパス解決とアプリの終了までやる）。
/// 直接動かすなら DB のパスを環境変数で渡す。
///
/// ```bash
/// LEDGER_SEED_DB=/path/to/ledgercore.sqlite flutter test tool/seed_dev_data.dart
/// ```
///
/// | 環境変数 | 既定 | 意味 |
/// | --- | --- | --- |
/// | `LEDGER_SEED_DB` | （必須） | 投入先の sqlite ファイル |
/// | `LEDGER_SEED_MONTHS` | 12 | 直近何か月ぶんを作るか |
/// | `LEDGER_SEED_RESET` | - | `1` なら既存の取引を全削除してから投入する |
/// | `LEDGER_SEED_APPEND` | - | `1` なら既存の取引を残したまま追記する |
/// | `LEDGER_SEED_SEED` | 20260908 | 乱数シード。変えると別の内容になる |
///
/// 既存の取引があるのに `LEDGER_SEED_RESET` も `LEDGER_SEED_APPEND` も無い場合は、
/// 二重投入を避けるため何もせず失敗する。
///
/// ## なぜ `flutter test` で動かすのか
///
/// `lib/db/database.dart` は `package:drift_flutter` を import しており Flutter に
/// 依存するため、`dart run` では解決できない。`flutter test` なら Flutter の下で
/// 動き、drift の DAO をそのまま使えるので `amount` の CHECK・外部キー・
/// `created_at` / `updated_at` の `clientDefault` をすべて実装どおりに通せる
/// （sqlite3 を直接叩くとこれらを手で守ることになる）。
///
/// CI の `flutter test` は既定で `test/` だけを探すので、このファイルは走らない。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';

import 'seed_data_builder.dart';

void main() {
  // `flutter test` はテストが 1 件も無いと失敗するので、投入処理を test() で包む。
  // 検証ではなく実行が目的なので、アサーションではなく例外で失敗させる。
  test('開発用のダミー取引を投入する', () async {
    final dbPath = Platform.environment['LEDGER_SEED_DB'];
    if (dbPath == null || dbPath.isEmpty) {
      fail(
        '投入先の DB が指定されていない。'
        'tool/seed_dev_data.sh から実行するか、LEDGER_SEED_DB に '
        'ledgercore.sqlite のパスを渡すこと。',
      );
    }

    final months = int.parse(
      Platform.environment['LEDGER_SEED_MONTHS'] ?? '12',
    );
    final seed = int.parse(
      Platform.environment['LEDGER_SEED_SEED'] ?? '20260908',
    );
    final reset = Platform.environment['LEDGER_SEED_RESET'] == '1';
    final append = Platform.environment['LEDGER_SEED_APPEND'] == '1';

    final file = File(dbPath);
    stdout.writeln('投入先: $dbPath');
    stdout.writeln(file.existsSync() ? '既存の DB を開く' : '新しい DB を作る');

    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      // 既存データの確認。件数を読むより先に開くことで、必要ならマイグレーションが走る。
      final existing = await db.select(db.transactions).get();
      if (existing.isNotEmpty && !reset && !append) {
        fail(
          '既に取引が ${existing.length} 件ある。'
          '入れ直すなら --reset、追記するなら --append を付けること。',
        );
      }
      // メンバーは onCreate では投入されない。0 人のまま取引だけ入れると
      // 起動時にデータ不整合と判定されるので、空なら 2 人ぶん作る。
      var members = await db.getMembers();
      if (members.isEmpty) {
        await db.insertInitialMembers('たろう', 'はなこ');
        members = await db.getMembers();
        stdout.writeln('メンバーを投入した: ${members.map((m) => m.name).join(' / ')}');
      } else {
        stdout.writeln('既存のメンバーを使う: ${members.map((m) => m.name).join(' / ')}');
      }

      final categories = await db.getCategories();
      final categoryIdsByName = {for (final c in categories) c.name: c.id};

      final seeds = buildSeedTransactions(
        now: DateTime.now(),
        categoryIdsByName: categoryIdsByName,
        memberIds: [for (final m in members) m.id],
        months: months,
        seed: seed,
      );

      // 既定のカテゴリ名を改名・削除した端末では、その費目が丸ごと飛ぶ。
      // 全部が一致しないと 0 件になるので、削除より前にここで止める
      // （--reset の削除を先にやると、取引が消えただけの DB が残る）。
      final skipped = seedCategoryNames.where(
        (name) => !categoryIdsByName.containsKey(name),
      );
      if (skipped.isNotEmpty) {
        stdout.writeln('対応するカテゴリが無いので飛ばす: ${skipped.join(' / ')}');
      }
      if (seeds.isEmpty) {
        fail(
          '投入できる取引が 1 件も作れなかった。'
          'カテゴリ名が既定（${seedCategoryNames.join(' / ')}）と一致しないか、'
          '対象期間が短すぎる。既存の取引は消していない。',
        );
      }

      if (existing.isNotEmpty && reset) {
        await db.delete(db.transactions).go();
        stdout.writeln('既存の取引 ${existing.length} 件を削除した');
      }

      // 1 件ずつ insertTransaction() を呼ぶと 360 回のクエリになるので batch で入れる。
      // created_at / updated_at は clientDefault が埋める。
      await db.batch((b) {
        b.insertAll(db.transactions, [
          for (final s in seeds)
            TransactionsCompanion.insert(
              memberId: s.memberId,
              categoryId: s.categoryId,
              amount: s.amount.toDouble(),
              spentAt: s.spentAt,
              memo: Value(s.memo),
            ),
        ]);
      });

      final total = seeds.fold<int>(0, (sum, s) => sum + s.amount);
      stdout.writeln(
        '投入した取引: ${seeds.length} 件 '
        '(${_ym(seeds.first.spentAt)} 〜 ${_ym(seeds.last.spentAt)})',
      );
      stdout.writeln('合計金額: ¥$total');
    } finally {
      await db.close();
    }
  });
}

String _ym(DateTime at) => '${at.year}-${at.month.toString().padLeft(2, '0')}';
