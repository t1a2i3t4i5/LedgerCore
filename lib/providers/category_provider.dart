import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../models/category.dart';

class CategoryProvider extends ChangeNotifier {
  final AppDatabase _db;

  List<CategoryView> _categories = [];
  bool _loading = false;
  String? _error;

  CategoryProvider(this._db);

  List<CategoryView> get categories => _categories;
  bool get loading => _loading;
  String? get error => _error;

  /// カテゴリ一覧を取得する
  Future<void> fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _categories = await _db.getCategories();
    } catch (e) {
      _error = e.toString();
      debugPrint('CategoryProvider.fetch エラー: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// カテゴリを追加する
  Future<void> create(String name) async {
    await _db.insertCategory(name);
    await fetch();
  }

  /// カテゴリを更新する
  Future<void> update(int categoryId, String name) async {
    await _db.updateCategoryName(categoryId, name);
    await fetch();
  }

  /// カテゴリを削除する
  Future<void> delete(int categoryId) async {
    await _db.deleteCategory(categoryId);
    await fetch();
  }
}
