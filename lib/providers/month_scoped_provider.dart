import 'package:flutter/foundation.dart';

import '../logging/operation_logger.dart';

/// 「今」を返す関数。既定は [DateTime.now] で、テストから固定時刻を注入するための口。
typedef Clock = DateTime Function();

/// 表示中の年月を持つ Provider の共通部分。
///
/// 「今が何月か」の判断材料を [Clock] 1 つに閉じ込める。初期表示月・
/// [isCurrentMonth]・[goToCurrentMonth] はすべてここから導かれるので、
/// 画面側が `DateTime.now()` を読み直す必要はない。
///
/// 月をまたぐ操作は [fetch] まで面倒を見る。表示月だけ変えて再取得を
/// 忘れる経路を残さないため。
abstract class MonthScopedProvider extends ChangeNotifier {
  final Clock _clock;

  /// 操作ログの出力先。サブクラスからも使う。
  /// 省略時は何も書かないロガーなので、ログを見ないテストは今までどおり書ける
  @protected
  final OperationLogger logger;

  late int _year;
  late int _month;

  MonthScopedProvider({Clock? clock, OperationLogger? logger})
    : _clock = clock ?? DateTime.now,
      logger = logger ?? OperationLogger.noop() {
    final now = _clock();
    _year = now.year;
    _month = now.month;
  }

  int get year => _year;
  int get month => _month;

  /// 表示中の年月が [Clock] の指す「今月」と一致するか
  bool get isCurrentMonth {
    final now = _clock();
    return _year == now.year && _month == now.month;
  }

  /// 表示月を設定する。再取得しないので、production からは使わない
  /// （[changeMonth] / [goToCurrentMonth] を使うこと）。
  ///
  /// 再取得を伴わない setter を公開したままにすると、月ジャンプ機能を足す人が
  /// 素直にこれを選び、「月を変えたのに中身が前の月のまま」の経路が復活する。
  /// 範囲外の月は [DateTime] の正規化で 1〜12 に丸める — 生の値を通すと
  /// `getTransactionsByMonth(2026, 13)` が 2027 年 1 月のデータを返しつつ
  /// ヘッダだけ「2026年13月」になる
  @visibleForTesting
  void setYearMonth(int year, int month) {
    final normalized = DateTime(year, month);
    _year = normalized.year;
    _month = normalized.month;
    notifyListeners();
  }

  /// 表示月を [year] 年 [month] 月へ移し、その月のデータを読み直す。
  ///
  /// 相対移動でない月ジャンプの唯一の入口。[setYearMonth] と違って再取得まで
  /// 面倒を見るので、production から表示月を動かすときはこれを使う。
  ///
  /// 月の移動はすべてここを通る（[changeMonth] も [goToCurrentMonth] も
  /// これを呼ぶ）ので、`month.change` のログもここに 1 つ置けば足りる。
  /// [via] は入口の区別（`arrow` / `jump` / `current`）で、ログにだけ載る
  Future<void> goToMonth(int year, int month, {String via = 'jump'}) async {
    final from = _logMonth(_year, _month);
    setYearMonth(year, month);
    // 記録するのは丸めた**後**の月。setYearMonth は 13 月を翌年 1 月へ
    // 正規化するので、引数をそのまま書くとログだけ 2026-13 になる
    logger.info(
      'month.change',
      detail: {'from': from, 'to': _logMonth(_year, _month), 'via': via},
    );
    await fetch();
  }

  /// 表示月を [delta] か月ぶん送り、その月のデータを読み直す。
  /// 12 月 → 翌年 1 月、1 月 → 前年 12 月の繰り上げ・繰り下げを含む
  Future<void> changeMonth(int delta) async {
    // DateTime は月の桁あふれを正規化するので、繰り上げ・繰り下げを自前で
    // 書かずに済む（13 月 → 翌年 1 月、0 月 → 前年 12 月）
    final shifted = DateTime(_year, _month + delta);
    await goToMonth(shifted.year, shifted.month, via: 'arrow');
  }

  /// 今月へ戻り、その月のデータを読み直す
  Future<void> goToCurrentMonth() async {
    final now = _clock();
    await goToMonth(now.year, now.month, via: 'current');
  }

  /// 注入された [Clock] が返す「今」。
  ///
  /// サブクラスが表示月とは**別の軸**を持つときに使う（集計画面の年モードが
  /// 該当する）。`_clock` そのものを公開しないのは、「今がいつか」の判断材料を
  /// このクラスに閉じたままにするため。
  ///
  /// **年の軸をここに足さないこと。** `_year` は表示月の一部で、動かせば
  /// [fetch] の対象月ごと変わる。年単位の表示は、この年月とは独立した軸を
  /// サブクラス側に持たせる（`SummaryProvider` 参照）。
  @protected
  DateTime now() => _clock();

  /// 表示月ぶんのデータを読み直す。サブクラスが実装する
  Future<void> fetch();
}

/// ログに載せる年月の書式（`2026-08`）。
///
/// 画面用の `widgets/period_format.dart` の `formatPeriod()`（`2026年8月`）を
/// 使わないのは、ログが機械可読を優先して桁を固定するため。
/// **画面にこの書式を出さないこと** — 年月の表示は今までどおり
/// `formatPeriod()` / `formatPeriodShort()` に寄せる
String _logMonth(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';
