import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../models/transaction.dart';
import 'month_scoped_provider.dart';

// ソート対象
enum TransactionSortField { spentAt, amount }

// ソート順
enum SortOrder { asc, desc }

class TransactionProvider extends MonthScopedProvider {
  final AppDatabase _db;

  List<TransactionView> _transactions = [];
  bool _loading = false;
  String? _error;

  // ---- ソート状態 ----
  TransactionSortField _sortField = TransactionSortField.spentAt;
  SortOrder _sortOrder = SortOrder.desc;

  // ---- フィルター状態 ----
  Set<int> _filterCategoryIds = {};
  Set<int> _filterUserIds = {};
  double? _filterMinAmount;
  double? _filterMaxAmount;
  String _filterMemoQuery = '';

  TransactionProvider(this._db, {super.clock});

  // ---- 基本 getter ----（year / month は MonthScopedProvider が持つ）
  List<TransactionView> get transactions => _transactions;
  bool get loading => _loading;
  String? get error => _error;

  // ---- ソート・フィルター getter ----
  TransactionSortField get sortField => _sortField;
  SortOrder get sortOrder => _sortOrder;
  Set<int> get filterCategoryIds => _filterCategoryIds;
  Set<int> get filterUserIds => _filterUserIds;
  double? get filterMinAmount => _filterMinAmount;
  double? get filterMaxAmount => _filterMaxAmount;
  String get filterMemoQuery => _filterMemoQuery;

  // フィルター・ソートを適用した取引リスト
  List<TransactionView> get filteredTransactions {
    final filtered = _transactions.where((t) {
      if (_filterCategoryIds.isNotEmpty &&
          !_filterCategoryIds.contains(t.categoryId)) {
        return false;
      }
      if (_filterUserIds.isNotEmpty && !_filterUserIds.contains(t.userId)) {
        return false;
      }
      if (_filterMinAmount != null && t.amount < _filterMinAmount!) {
        return false;
      }
      if (_filterMaxAmount != null && t.amount > _filterMaxAmount!) {
        return false;
      }
      if (_filterMemoQuery.isNotEmpty) {
        final q = _filterMemoQuery.toLowerCase();
        final memo = (t.memo ?? '').toLowerCase();
        if (!memo.contains(q)) return false;
      }
      return true;
    }).toList();

    int cmp(TransactionView a, TransactionView b) {
      final c = switch (_sortField) {
        TransactionSortField.spentAt => a.spentAt.compareTo(b.spentAt),
        TransactionSortField.amount => a.amount.compareTo(b.amount),
      };
      return _sortOrder == SortOrder.asc ? c : -c;
    }

    filtered.sort(cmp);
    return filtered;
  }

  // 適用中のフィルター数（バッジ表示用）
  int get activeFilterCount {
    var n = 0;
    if (_filterCategoryIds.isNotEmpty) n++;
    if (_filterUserIds.isNotEmpty) n++;
    if (_filterMinAmount != null || _filterMaxAmount != null) n++;
    if (_filterMemoQuery.isNotEmpty) n++;
    return n;
  }

  // フィルター適用後の合計金額
  double get filteredTotal =>
      filteredTransactions.fold(0.0, (sum, t) => sum + t.amount);

  /// ソート条件を設定する
  void setSort(TransactionSortField field, SortOrder order) {
    _sortField = field;
    _sortOrder = order;
    notifyListeners();
  }

  /// フィルターを一括設定する
  void setFilters({
    Set<int>? categoryIds,
    Set<int>? userIds,
    double? minAmount,
    double? maxAmount,
    String? memoQuery,
  }) {
    _filterCategoryIds = categoryIds ?? {};
    _filterUserIds = userIds ?? {};
    _filterMinAmount = minAmount;
    _filterMaxAmount = maxAmount;
    _filterMemoQuery = memoQuery ?? '';
    notifyListeners();
  }

  /// フィルターを全てクリアする
  void resetFilters() {
    _filterCategoryIds = {};
    _filterUserIds = {};
    _filterMinAmount = null;
    _filterMaxAmount = null;
    _filterMemoQuery = '';
    notifyListeners();
  }

  /// 取引一覧を取得する
  @override
  Future<void> fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _transactions = await _db.getTransactionsByMonth(year, month);
    } catch (e) {
      _error = e.toString();
      debugPrint('TransactionProvider.fetch エラー: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 取引を追加する
  Future<void> create(TransactionInput input) async {
    await _db.insertTransaction(input);
    await fetch();
  }

  /// 取引を更新する
  Future<void> update(int transactionId, TransactionInput input) async {
    await _db.updateTransaction(transactionId, input);
    await fetch();
  }

  /// 取引を削除する
  Future<void> delete(int transactionId) async {
    await _db.deleteTransaction(transactionId);
    await fetch();
  }
}
