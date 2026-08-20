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
  Set<int> _filterMemberIds = {};
  double? _filterMinAmount;
  double? _filterMaxAmount;
  String _filterMemoQuery = '';

  TransactionProvider(this._db, {super.clock, super.logger});

  // ---- 基本 getter ----（year / month は MonthScopedProvider が持つ）
  List<TransactionView> get transactions => _transactions;
  bool get loading => _loading;
  String? get error => _error;

  // ---- ソート・フィルター getter ----
  TransactionSortField get sortField => _sortField;
  SortOrder get sortOrder => _sortOrder;
  Set<int> get filterCategoryIds => _filterCategoryIds;
  Set<int> get filterMemberIds => _filterMemberIds;
  double? get filterMinAmount => _filterMinAmount;
  double? get filterMaxAmount => _filterMaxAmount;
  String get filterMemoQuery => _filterMemoQuery;

  // フィルター・ソートを適用した取引リスト
  List<TransactionView> get filteredTransactions {
    final filtered =
        _transactions.where((t) {
          if (_filterCategoryIds.isNotEmpty &&
              !_filterCategoryIds.contains(t.categoryId)) {
            return false;
          }
          if (_filterMemberIds.isNotEmpty &&
              !_filterMemberIds.contains(t.memberId)) {
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
    if (_filterMemberIds.isNotEmpty) n++;
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
    logger.info('transaction.sort', detail: {'field': field, 'order': order});
    notifyListeners();
  }

  /// フィルターを一括設定する
  void setFilters({
    Set<int>? categoryIds,
    Set<int>? memberIds,
    double? minAmount,
    double? maxAmount,
    String? memoQuery,
  }) {
    _filterCategoryIds = categoryIds ?? {};
    _filterMemberIds = memberIds ?? {};
    _filterMinAmount = minAmount;
    _filterMaxAmount = maxAmount;
    _filterMemoQuery = memoQuery ?? '';
    logger.info(
      'transaction.filter',
      detail: {
        'activeCount': activeFilterCount,
        // 空の Set はキーごと落とす（絞っていない軸を毎行書いても読む情報が増えない）
        'categoryIds': _filterCategoryIds.isEmpty ? null : _filterCategoryIds,
        'memberIds': _filterMemberIds.isEmpty ? null : _filterMemberIds,
        'hasAmountRange': _filterMinAmount != null || _filterMaxAmount != null,
        // **検索語そのものは書かない。** メモ本文を書かないのと同じ理由で、
        // 「◯◯病院」を検索した事実が残るのは本文が残るのとほぼ変わらない
        'hasMemoQuery': _filterMemoQuery.isNotEmpty,
      },
    );
    notifyListeners();
  }

  /// フィルターを全てクリアする
  void resetFilters() {
    _filterCategoryIds = {};
    _filterMemberIds = {};
    _filterMinAmount = null;
    _filterMaxAmount = null;
    _filterMemoQuery = '';
    logger.info('transaction.filter.reset');
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
      logger.error(
        'transaction.fetch',
        e,
        detail: {'year': year, 'month': month},
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 取引を追加する
  Future<void> create(TransactionInput input) async {
    final detail = _inputDetail(input);
    try {
      await _db.insertTransaction(input);
    } catch (e) {
      logger.error('transaction.create', e, detail: detail);
      // **必ず rethrow する。** この try は失敗をログに残すためだけのもので、
      // 例外は今までどおり画面（add_transaction_screen.dart）の catch まで
      // 届かせる。握ると保存に失敗しても SnackBar が出ず、黙って消える
      rethrow;
    }
    // insertTransaction は採番された id を返さないので、追加のログに id は無い
    logger.info('transaction.create', detail: detail);
    await fetch();
  }

  /// 取引を更新する
  Future<void> update(int transactionId, TransactionInput input) async {
    final detail = {'id': transactionId, ..._inputDetail(input)};
    try {
      await _db.updateTransaction(transactionId, input);
    } catch (e) {
      logger.error('transaction.update', e, detail: detail);
      rethrow;
    }
    logger.info('transaction.update', detail: detail);
    await fetch();
  }

  /// 取引を削除する
  Future<void> delete(int transactionId) async {
    final detail = {'id': transactionId};
    try {
      await _db.deleteTransaction(transactionId);
    } catch (e) {
      logger.error('transaction.delete', e, detail: detail);
      rethrow;
    }
    logger.info('transaction.delete', detail: detail);
    await fetch();
  }

  /// 取引の入力内容からログの `detail` を組み立てる。
  ///
  /// **メモ本文は載せない。** 家計簿のメモは「◯◯病院」「◯◯さんへの祝儀」の
  /// ように機微になりうる一方、ログファイルは端末外へ持ち出されうる。
  /// 「メモを付けたか・どれくらいの長さか」は文字数で足りる
  Map<String, Object?> _inputDetail(TransactionInput input) => {
    'amount': input.amount,
    'categoryId': input.categoryId,
    'memberId': input.memberId,
    'spentAt': input.spentAt,
    'memoLength': input.memo?.length,
  };
}
