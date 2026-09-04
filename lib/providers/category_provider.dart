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
  Future<void> create(String name, {int? colorValue}) async {
    // insertCategory は採番された id を返さないので、追加のログに id は無い。
    // カテゴリ名はユーザー自身が付けた短いラベルで画面にも常時出ているため、
    // 取引のメモと違ってそのまま載せる
    final detail = {
      'name': name,
      if (colorValue != null) 'colorValue': colorValue,
    };
    try {
      await _db.insertCategory(name, colorValue: colorValue);
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
  Future<void> update(int categoryId, String name, {int? colorValue}) async {
    final detail = {
      'id': categoryId,
      'name': name,
      if (colorValue != null) 'colorValue': colorValue,
    };
    try {
      if (colorValue == null) {
        await _db.updateCategoryName(categoryId, name);
      } else {
        await _db.updateCategory(categoryId, name, colorValue);
      }
    } catch (e) {
      _logger.error('category.update', e, detail: detail);
      rethrow;
    }
    _logger.info('category.update', detail: detail);
    await fetch();
  }

  /// 並べ替えできるカテゴリ。固定カテゴリは常に末尾なので、この並びの添字は
  /// [categories] の添字とそのまま一致する。
  List<CategoryView> get movableCategories =>
      _categories.where((category) => !category.isFixed).toList();

  /// 固定カテゴリ。通常は 0〜1 件だが、壊れた旧データが来ても画面から
  /// 行を隠さないよう、一覧として返す。
  List<CategoryView> get fixedCategories =>
      _categories.where((category) => category.isFixed).toList();

  /// カテゴリの並び順を更新する。
  ///
  /// 添字は [movableCategories] のもの。固定カテゴリは受け皿として末尾に
  /// 据え置くので、範囲外が来たら何もしない。
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final movable = movableCategories;
    if (oldIndex < 0 ||
        oldIndex >= movable.length ||
        newIndex < 0 ||
        newIndex >= movable.length) {
      return;
    }

    final previous = List<CategoryView>.of(_categories);
    final reordered = List<CategoryView>.of(movable);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    _categories = [
      for (final (index, category) in reordered.indexed)
        CategoryView(
          id: category.id,
          name: category.name,
          colorValue: category.colorValue,
          sortOrder: index,
          isFixed: category.isFixed,
        ),
      ...previous.where((category) => category.isFixed),
    ];
    notifyListeners();

    // 固定カテゴリの sort_order は書き換えない。
    final ids = reordered.map((category) => category.id).toList();
    final detail = {'ids': ids};
    try {
      await _db.reorderCategories(ids);
    } catch (e) {
      _categories = previous;
      _logger.error('category.reorder', e, detail: detail);
      notifyListeners();
      rethrow;
    }
    _logger.info('category.reorder', detail: detail);
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
