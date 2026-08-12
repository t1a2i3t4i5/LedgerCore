import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../models/summary.dart';
import '../models/split.dart';
import 'month_scoped_provider.dart';

class SummaryProvider extends MonthScopedProvider {
  final AppDatabase _db;

  MonthlySummary? _summary;
  SplitResult? _split;
  bool _loading = false;
  String? _error;

  SummaryProvider(this._db, {super.clock});

  // year / month は MonthScopedProvider が持つ
  MonthlySummary? get summary => _summary;
  SplitResult? get split => _split;
  bool get loading => _loading;
  String? get error => _error;

  /// 月次サマリーと割り勘情報を端末内DBから計算する
  @override
  Future<void> fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _summary = await _db.getMonthlySummary(year, month);
      _split = await _db.getSplit(year, month);
    } catch (e) {
      _error = e.toString();
      debugPrint('SummaryProvider.fetch エラー: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
