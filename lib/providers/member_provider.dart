import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../models/household_member.dart';

/// 割り勘の対象となるメンバーを端末内で管理する。
class MemberProvider extends ChangeNotifier {
  final AppDatabase _db;

  List<HouseholdMember> _members = [];
  bool _membersLoading = false;

  MemberProvider(this._db);

  List<HouseholdMember> get members => _members;
  bool get membersLoading => _membersLoading;

  /// メンバー一覧を取得する
  Future<void> fetchMembers() async {
    _membersLoading = true;
    notifyListeners();
    try {
      _members = await _db.getMembers();
    } catch (e) {
      debugPrint('MemberProvider.fetchMembers エラー: $e');
    } finally {
      _membersLoading = false;
      notifyListeners();
    }
  }

  /// メンバーを追加する
  Future<void> addMember(String name, {String? mail}) async {
    await _db.insertMember(name, mail: mail);
    await fetchMembers();
  }

  /// メンバー名を変更する
  Future<void> updateMember(int id, String name) async {
    await _db.updateMemberName(id, name);
    await fetchMembers();
  }

  /// メンバーを削除する
  Future<void> deleteMember(int id) async {
    await _db.deleteMember(id);
    await fetchMembers();
  }
}
