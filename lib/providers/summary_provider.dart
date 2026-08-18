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

  /// 年モード・全期間モードが見ている年。**表示月（[year] / [month]）とは
  /// 独立した軸**で、年を送ってもここだけが動く。
  ///
  /// 表示月の年（`MonthScopedProvider.year`）を年送りに使ってはいけない。
  /// あれは [fetch] が月次サマリーと割り勘を取る対象そのものなので、動かすと
  /// **割り勘タブの表示期間が 1 年ぶん巻き込まれる**（`SummaryProvider` は
  /// 集計タブと割り勘タブで 1 インスタンス）。「月の数値さえ保てば無事」では
  /// なく、実測で割り勘タブが `2026年7月 / ¥700` から `2025年7月 / ¥250` に
  /// 化けた。ユーザーは割り勘タブで何も操作していないので理由が分からない。
  late int _yearAxis;

  SummaryProvider(this._db, {super.clock, super.logger}) {
    _yearAxis = year;
  }

  // year / month は MonthScopedProvider が持つ
  MonthlySummary? get summary => _summary;
  SplitResult? get split => _split;
  SummaryPeriod get period => _period;

  /// 年モード・全期間モードのヘッダに出す年
  int get yearAxis => _yearAxis;

  /// 年の軸が [Clock] の指す「今年」と一致するか
  bool get isCurrentYear => _yearAxis == now().year;

  /// 年モードで表示する年次サマリー。年モード以外では null
  YearlySummary? get yearly => _yearly;

  /// 全期間モードで表示する年別合計。取引のある年だけが昇順に並ぶ。
  /// 全期間モード以外では空
  List<PeriodTotal> get allYears => _allYears;

  bool get loading => _loading;
  String? get error => _error;

  /// 表示期間を切り替え、その期間ぶんを読み直す。
  ///
  /// 年モードへ入るときは年の軸を表示月の年に合わせる。前に年モードで見ていた
  /// 年を覚えていると、月モードで別の年へ移ったあとに年モードへ戻ったときへ
  /// 「今見ている月と無関係な年」が出る。
  Future<void> setPeriod(SummaryPeriod period) async {
    // 同じモードを選び直したときは何も変わらないので、ログにも残さない
    if (_period == period) return;
    final from = _period;
    _period = period;
    if (period == SummaryPeriod.year) _yearAxis = year;
    logger.info('summary.period', detail: {'from': from, 'to': period});
    // 先に通知しておく。fetch の await を待つとセグメントの選択だけが
    // 一拍遅れて動き、押しても効かなかったように見える
    notifyListeners();
    await fetch();
  }

  /// 年の軸を [delta] 年ぶん送り、読み直す。**表示月には触らない。**
  ///
  /// `goToMonth(year + delta, month)` にしてはいけない理由は [_yearAxis] を
  /// 参照。割り勘タブの表示期間ごと動く。
  Future<void> changeYear(int delta) async {
    final from = _yearAxis;
    _yearAxis += delta;
    // 表示月の `month.change` とは別の op にする。この 2 つは別の軸で、
    // 同じ op にまとめるとログから「どちらが動いたのか」が読めなくなる
    logger.info('summary.year', detail: {'from': from, 'to': _yearAxis});
    await fetch();
  }

  /// 年の軸を今年へ戻し、読み直す。**表示月には触らない。**
  Future<void> goToCurrentYear() async {
    final from = _yearAxis;
    _yearAxis = now().year;
    logger.info('summary.year', detail: {'from': from, 'to': _yearAxis});
    await fetch();
  }

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
          ? await _db.getYearlySummary(_yearAxis)
          : null;
      _allYears = _period == SummaryPeriod.all
          ? await _db.getYearlyTotals()
          : const [];
    } catch (e) {
      _error = e.toString();
      logger.error('summary.fetch', e, detail: {
        'year': year,
        'month': month,
        'period': _period,
        'yearAxis': _yearAxis,
      });
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
