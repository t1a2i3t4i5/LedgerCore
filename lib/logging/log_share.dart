import 'dart:ui';

/// 画面が触る共有の入口。ファイルや共有プラグインを画面へ持ち込まない。
abstract class LogShare {
  /// 押下時点までのログを共有する。読み出しは呼び出し時に予約する。
  /// false は共有できるログがない場合だけ。キャンセルは true、失敗は例外。
  Future<bool> share({required Rect origin});
}

/// ログの保存先が取れない端末と、共有を使わないテスト向け。
class NoopLogShare implements LogShare {
  const NoopLogShare();

  @override
  Future<bool> share({required Rect origin}) async => false;
}
