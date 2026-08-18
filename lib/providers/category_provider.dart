import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../logging/operation_logger.dart';
import '../models/category.dart';

class CategoryProvider extends ChangeNotifier {
  final AppDatabase _db;

  /// 操作ログの出力先。省略時は何も書かないので、
  /// ログを見ないテストは今までどおり `CategoryProvider(db)` で書ける
  final OperationLogger _logger;

  List<CategoryView> _categories = [];
  bool _loading = false;
  String? _error;

  CategoryProvider(this._db, {OperationLogger? logger})
      : _logger = logger ?? OperationLogger.noop();

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
      _logger.error('category.fetch', e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// カテゴリを追加する
  Future<void> create(String name) async {
    // insertCategory は採番された id を返さないので、追加のログに id は無い。
    // カテゴリ名はユーザー自身が付けた短いラベルで画面にも常時出ているため、
    // 取引のメモと違ってそのまま載せる
    final detail = {'name': name};
    try {
      await _db.insertCategory(name);
    } catch (e) {
      _logger.error('category.create', e, detail: detail);
      // **必ず rethrow する。** 例外は画面（categories_screen.dart）の catch へ
      // 届かせる。握ると重複名などの失敗が黙って消える
      rethrow;
    }
    _logger.info('category.create', detail: detail);
    await fetch();
  }

  /// カテゴリを更新する
  Future<void> update(int categoryId, String name) async {
    final detail = {'id': categoryId, 'name': name};
    try {
      await _db.updateCategoryName(categoryId, name);
    } catch (e) {
      _logger.error('category.update', e, detail: detail);
      rethrow;
    }
    _logger.info('category.update', detail: detail);
    await fetch();
  }

  /// カテゴリを削除する
  Future<void> delete(int categoryId) async {
    final detail = {'id': categoryId};
    try {
      await _db.deleteCategory(categoryId);
    } catch (e) {
      // 取引が紐づくカテゴリの削除は外部キー制約で落ちる。
      // 「なぜ消せなかったか」が残る数少ない経路なので error まで載せる
      _logger.error('category.delete', e, detail: detail);
      rethrow;
    }
    _logger.info('category.delete', detail: detail);
    await fetch();
  }
}
