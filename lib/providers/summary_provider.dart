import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../models/summary.dart';
import '../models/split.dart';

class SummaryProvider extends ChangeNotifier {
  final AppDatabase _db;

  MonthlySummaryResponse? _summary;
  SplitResponse? _split;
  bool _loading = false;
  String? _error;

  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  SummaryProvider(this._db);

  MonthlySummaryResponse? get summary => _summary;
  SplitResponse? get split => _split;
  bool get loading => _loading;
  String? get error => _error;
  int get year => _year;
  int get month => _month;

  void setYearMonth(int year, int month) {
    _year = year;
    _month = month;
    notifyListeners();
  }

  /// 月次サマリーと割り勘情報を端末内DBから計算する
  Future<void> fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _summary = await _db.getMonthlySummary(_year, _month);
      _split = await _db.getSplit(_year, _month);
    } catch (e) {
      _error = e.toString();
      debugPrint('SummaryProvider.fetch エラー: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
