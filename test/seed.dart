import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/household_member.dart';

/// テスト用にメンバーを用意する。
///
/// **`onCreate` はメンバーを 1 人も投入しない**（#144 で既定メンバー「自分」を
/// やめた）。メンバーが 0 人の DB で `LedgerApp` を pump すると初期設定画面が
/// 出るので、通常画面を検証するテストは pump の前にここを通す。
///
/// 2 人までの上限（`AppDatabase.insertMember`）を迂回できるよう INSERT を
/// 直接書いている。旧版由来で 3 人以上いる端末を再現するテストでも使う。
Future<List<HouseholdMember>> seedMembers(
  AppDatabase db, [
  List<String> names = const ['自分'],
]) async {
  for (final name in names) {
    await db.customStatement('INSERT INTO members (name) VALUES (?)', [name]);
  }
  return db.getMembers();
}
