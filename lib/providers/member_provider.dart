import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../logging/operation_logger.dart';
import '../models/household_member.dart';

/// 割り勘の対象となるメンバーを端末内で管理する。
class MemberProvider extends ChangeNotifier {
  final AppDatabase _db;

  /// 操作ログの出力先。省略時は何も書かない
  final OperationLogger _logger;

  List<HouseholdMember> _members = [];
  bool _membersLoading = false;

  MemberProvider(this._db, {OperationLogger? logger})
    : _logger = logger ?? OperationLogger.noop();

  List<HouseholdMember> get members => _members;
  bool get membersLoading => _membersLoading;

  /// メンバー一覧を取得する
  Future<void> fetchMembers() async {
    _membersLoading = true;
    notifyListeners();
    try {
      _members = await _db.getMembers();
    } catch (e) {
      _logger.error('member.fetch', e);
    } finally {
      _membersLoading = false;
      notifyListeners();
    }
  }

  /// 初期設定で 2 人をまとめて登録する。
  ///
  /// 途中で失敗したら 1 人も登録されない（[AppDatabase.insertInitialMembers]
  /// が 1 トランザクションで入れる）。次の起動でも初期設定が出る状態を保つ。
  Future<void> createInitialMembers(String first, String second) async {
    final detail = {
      'names': [first, second],
    };
    try {
      await _db.insertInitialMembers(first, second);
    } catch (e) {
      _logger.error('member.setup', e, detail: detail);
      // **必ず rethrow する。** 例外は画面（initial_setup_screen.dart）の
      // catch へ届いて SnackBar になり、入力し直せる
      rethrow;
    }
    _logger.info('member.setup', detail: detail);
    await fetchMembers();
  }

  /// メンバーを追加する
  Future<void> addMember(String name) async {
    // op 名は `member.create` に揃える（メソッド名は addMember だが、
    // カテゴリ・取引と同じ `<対象>.<動作>` の形にしたほうがログを追いやすい）。
    // insertMember は採番された id を返さないので追加のログに id は無い
    final detail = {'name': name};
    try {
      await _db.insertMember(name);
    } catch (e) {
      _logger.error('member.create', e, detail: detail);
      // **必ず rethrow する。** 例外は画面（members_screen.dart）の catch へ
      rethrow;
    }
    _logger.info('member.create', detail: detail);
    await fetchMembers();
  }

  /// メンバー名を変更する
  Future<void> updateMember(int id, String name) async {
    final detail = {'id': id, 'name': name};
    try {
      await _db.updateMemberName(id, name);
    } catch (e) {
      _logger.error('member.update', e, detail: detail);
      rethrow;
    }
    _logger.info('member.update', detail: detail);
    await fetchMembers();
  }

  /// メンバーの識別色を変更する
  Future<void> updateMemberColor(int id, int colorValue) async {
    final detail = {'id': id, 'colorValue': colorValue};
    try {
      await _db.updateMemberColor(id, colorValue);
    } catch (e) {
      _logger.error('member.update', e, detail: detail);
      rethrow;
    }
    _logger.info('member.update', detail: detail);
    await fetchMembers();
  }

  /// メンバーを削除する
  Future<void> deleteMember(int id) async {
    final detail = {'id': id};
    try {
      await _db.deleteMember(id);
    } catch (e) {
      // 取引の支払者になっているメンバーの削除は外部キー制約で落ちる
      _logger.error('member.delete', e, detail: detail);
      rethrow;
    }
    _logger.info('member.delete', detail: detail);
    await fetchMembers();
  }
}
