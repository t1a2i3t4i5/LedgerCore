import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../models/summary.dart';
import '../models/split.dart';
import 'month_scoped_provider.dart';

/// 集計画面の表示期間。
///
/// **画面の `State` ではなく Provider が持つ。** `main_screen.dart` は
/// `IndexedStack` を使わず `body: _screens[_currentIndex]` でタブを差し替えるので、
/// タブを離れると `SummaryScreen` の `State` は破棄される。モードを画面に持たせると、
/// 取引タブを覗いて戻っただけで月モードに戻る。
enum SummaryPeriod {
  /// 単月。合計・カテゴリ別・メンバー別を出す
  month,

  /// 選択年。月別の推移グラフと、その年のカテゴリ別を出す
  year,

  /// 全期間。年別の推移グラフだけを出す
  all,
}

class SummaryProvider extends MonthScopedProvider {
  final AppDatabase _db;

  MonthlySummary? _summary;
  SplitResult? _split;
  SummaryPeriod _period = SummaryPeriod.month;
  YearlySummary? _yearly;
  List<PeriodTotal> _allYears = const [];
  bool _loading = false;
  String? _error;

  SummaryProvider(this._db, {super.clock});

  // year / month は MonthScopedProvider が持つ
  MonthlySummary? get summary => _summary;
  SplitResult? get split => _split;
  SummaryPeriod get period => _period;

  /// 年モードで表示する年次サマリー。年モード以外では null
  YearlySummary? get yearly => _yearly;

  /// 全期間モードで表示する年別合計。取引のある年だけが昇順に並ぶ。
  /// 全期間モード以外では空
  List<PeriodTotal> get allYears => _allYears;

  bool get loading => _loading;
  String? get error => _error;

  /// 表示期間を切り替え、その期間ぶんを読み直す
  Future<void> setPeriod(SummaryPeriod period) async {
    if (_period == period) return;
    _period = period;
    // 先に通知しておく。fetch の await を待つとセグメントの選択だけが
    // 一拍遅れて動き、押しても効かなかったように見える
    notifyListeners();
    await fetch();
  }

  /// 表示年を [delta] 年ぶん送り、読み直す。**月は保つ。**
  ///
  /// 月まで動かさないのは、同じ Provider を割り勘タブと共有しているため
  /// （[goToCurrentYear] と同じ理由）。
  Future<void> changeYear(int delta) async => goToMonth(year + delta, month);

  /// 表示中の期間ぶんの集計を端末内 DB から計算する
  @override
  Future<void> fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // 月次サマリーと割り勘は**モードに関わらず常に取る。**
      // 割り勘タブ（SplitScreen）が同じ SummaryProvider を共有していて
      // （main.dart の MultiProvider に 1 インスタンスしかない）、集計タブが
      // 年モードだからという理由で split を落とすと、割り勘タブを開いた人に
      // 「データがありません」が出る。月次サマリーも月モードの合計カードと
      // カテゴリ別に要る
      _summary = await _db.getMonthlySummary(year, month);
      _split = await _db.getSplit(year, month);

      // 年次データだけをモードで出し分ける。全部を毎回取ると、月モードしか
      // 使わない人が年 1 回ぶんの全取引を読むことになる
      //
      // 使わないモードでは捨てる。残すと「年を送る → 月モードへ戻す →
      // また年モードへ」の途中で、前の年のグラフを一瞬描く経路ができる
      _yearly = _period == SummaryPeriod.year
          ? await _db.getYearlySummary(year)
          : null;
      _allYears = _period == SummaryPeriod.all
          ? await _db.getYearlyTotals()
          : const [];
    } catch (e) {
      _error = e.toString();
      debugPrint('SummaryProvider.fetch エラー: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
