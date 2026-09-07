import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../logging/operation_logger.dart';

/// 起動直後にどの画面を出すかを表す状態。
enum StartupPhase {
  /// DB の読み取り中。まだどちらとも判断できない
  loading,

  /// 新規の端末。初期設定でメンバー 2 人を登録してもらう
  setup,

  /// 通常起動。メンバーが登録済み
  ready,

  /// メンバー 0 件なのに取引が残っている。データ不整合
  inconsistent,

  /// DB の読み取りに失敗した。0 件扱いにはしない
  failed,
}

/// 起動時にホームを出すか初期設定を出すかを、DB の状態だけから判定する。
///
/// **初回かどうかのフラグを別に持たない。** `shared_preferences` などに印を
/// 置くと、DB を消してもフラグだけ残る／その逆の組み合わせが生まれ、
/// 「メンバーが 0 人なのに通常画面」を作れてしまう。正常な新規 DB は
/// 「メンバー 0 件・取引 0 件」、初期設定を終えた端末と既存端末は
/// 「メンバー 1 件以上」で、この 2 つだけで判定できる。
///
/// メンバー 0 件でも取引が残っている DB は [StartupPhase.inconsistent] とし、
/// 初期設定へ送らない。既存の取引と無関係なメンバーを新しく足すことになり、
/// 誰が払ったのかが取り返しのつかない形で変わるため。復旧機能は持たない。
class StartupProvider extends ChangeNotifier {
  final AppDatabase _db;

  /// 操作ログの出力先。省略時は何も書かない
  final OperationLogger _logger;

  StartupPhase _phase = StartupPhase.loading;

  StartupProvider(this._db, {OperationLogger? logger})
    : _logger = logger ?? OperationLogger.noop();

  StartupPhase get phase => _phase;

  /// DB を読んで起動フェーズを決める。再試行と、初期設定を終えた直後にも呼ぶ。
  Future<void> load() async {
    _phase = StartupPhase.loading;
    notifyListeners();
    try {
      final memberCount = await _db.countMembers();
      if (memberCount > 0) {
        // 旧版由来で 3 人以上いる端末も通常起動にする（初期設定へ戻さない）
        _phase = StartupPhase.ready;
      } else {
        final transactionCount = await _db.countTransactions();
        if (transactionCount > 0) {
          // 読み取り自体は成功しても、この状態では起動を続けられない。
          // 共有ログから通常の読み取り失敗と区別できるよう件数を残す
          _logger.error(
            'startup.load',
            StateError('メンバーが0件なのに取引が残っています'),
            detail: {
              'memberCount': memberCount,
              'transactionCount': transactionCount,
            },
          );
          _phase = StartupPhase.inconsistent;
        } else {
          _phase = StartupPhase.setup;
        }
      }
    } catch (e) {
      // **読めなかったことを 0 件と混同しない。** 0 件扱いにすると、既存の
      // 家計簿を持つ端末に初期設定が出て、無関係なメンバーが増える
      _logger.error('startup.load', e);
      _phase = StartupPhase.failed;
    }
    notifyListeners();
  }
}
