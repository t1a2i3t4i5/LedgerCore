import '../db/database.dart';
import '../db/summary_calculator.dart';
import '../models/summary.dart';
import '../models/split.dart';
import 'month_scoped_provider.dart';

class SummaryProvider extends MonthScopedProvider {
  final AppDatabase _db;

  MonthlySummary? _summary;
  MonthlyComparisonView? _comparison;
  SplitResult? _split;
  bool _loading = false;
  String? _error;

  SummaryProvider(this._db, {super.clock, super.logger});

  // year / month は MonthScopedProvider が持つ
  MonthlySummary? get summary => _summary;

  /// 月モードだけで表示する、表示月とその前月の比較。
  MonthlyComparisonView? get comparison => _comparison;
  SplitResult? get split => _split;

  bool get loading => _loading;
  String? get error => _error;

  /// 表示中の期間ぶんの集計を端末内 DB から計算する
  @override
  Future<void> fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final summary = await _db.getMonthlySummary(year, month);
      _summary = summary;
      // 取得済みのサマリーの年月を使う。1月の前月は前年12月に正規化される。
      final previousMonth = DateTime(summary.year, summary.month - 1);
      final previous = await _db.getMonthlySummary(
        previousMonth.year,
        previousMonth.month,
      );
      _comparison = buildMonthlyComparison(summary, previous);
      _split = await _db.getSplit(year, month);
    } catch (e) {
      _error = e.toString();
      logger.error('summary.fetch', e, detail: {'year': year, 'month': month});
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
