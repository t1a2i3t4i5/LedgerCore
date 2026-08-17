import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/widgets/period_format.dart';

/// 年月の書式は月選択のヘッダと推移グラフのツールチップが共有する。
/// 実装から期待値を導くと（`'$year年$month月'` を組み立て直すなど）書式を
/// 変えても緑のままになるので、期待値はリテラルで書く
/// （`amount_format_test.dart` と同じ理由）。
void main() {
  group('formatPeriod', () {
    test('月ありは 年+月 の形にする', () {
      expect(formatPeriod(2026, 7), '2026年7月');
      expect(formatPeriod(2026, 12), '2026年12月');
      // 1 桁の月をゼロ埋めしない。MonthSelector が長く使ってきた形
      expect(formatPeriod(2026, 1), '2026年1月');
    });

    test('月が null なら年だけにする', () {
      expect(formatPeriod(2026, null), '2026年');
    });

    // 幅のテストが使う最大桁。年を 4 桁に丸めたりしないことを固定する
    test('桁が増えても年をそのまま出す', () {
      expect(formatPeriod(9999, 12), '9999年12月');
      expect(formatPeriod(9999, null), '9999年');
    });
  });

  group('formatPeriodShort', () {
    // 12 本並ぶ月別グラフの軸。年まで書くと 360px 幅で必ず重なる
    test('月ありは月だけにする', () {
      expect(formatPeriodShort(2026, 7), '7月');
      expect(formatPeriodShort(2026, 12), '12月');
      expect(formatPeriodShort(2026, 1), '1月');
    });

    // 年別の推移では年が唯一の識別子なので、短い形でも落とせない
    test('月が null なら年を残す', () {
      expect(formatPeriodShort(2026, null), '2026年');
      expect(formatPeriodShort(9999, null), '9999年');
    });

    // 短い形が長い形と同じになると、軸を短くした意味が無くなる
    test('月ありでは長い形より短い', () {
      for (final month in [1, 7, 12]) {
        expect(
          formatPeriodShort(2026, month).length,
          lessThan(formatPeriod(2026, month).length),
          reason: '$month 月',
        );
      }
    });
  });
}
