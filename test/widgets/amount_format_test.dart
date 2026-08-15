import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/widgets/amount_format.dart';

/// 画面テストが使う金額はすべて整数なので、書式を '#,###' から '#,##0.##' に
/// 変えても出力は 1 文字も変わらず、ウィジェットテストは 1 本も落ちない。
/// しかしそれは DB の整数 CHECK 制約の根拠そのものを崩す変更にあたる。
/// 小数を直接入れて確かめられるのはこのファイルだけなので、期待値は実装から
/// 導かずリテラルで書く（実装から導くと書式が変わっても緑のままになる）。
void main() {
  group('formatYen', () {
    test('¥ と 3 桁区切りを付けて返す', () {
      expect(formatYen(1200), '¥1,200');
      expect(formatYen(1234567), '¥1,234,567');
      expect(formatYen(999), '¥999');
    });

    // 取引一覧の合計パネルは 0 件のとき「合計 ¥0」を出す
    // （'#,###' は 0 を空文字にしない）
    test('0 は空文字ではなく ¥0 になる', () {
      expect(formatYen(0), '¥0');
    });

    // ここが DB の整数 CHECK 制約の根拠。小数部を出す書式に変えると
    // 「表示が小数を落とすから整数に限る」という理由が成り立たなくなる
    test('小数部は出さない', () {
      // half away from zero。移行で使う SQLite の ROUND と同じ丸め方
      expect(formatYen(1234.5), '¥1,235');
      expect(formatYen(1234.4), '¥1,234');
      expect(formatYen(0.4), '¥0');
      // 割り勘の fairShare（合計 ÷ 人数）は割り切れない値になりうる
      expect(formatYen(10000 / 3), '¥3,333');

      for (final v in [0.4, 1234.5, 10000 / 3, kMaxAmount / 7]) {
        expect(formatYen(v), isNot(contains('.')), reason: '$v');
      }
    });

    // 割り勘のマイナス残高。¥ の後ろに符号が来る既存の表示を固定する
    test('負値は ¥ の後ろに符号が付く', () {
      expect(formatYen(-1200), '¥-1,200');
    });

    // 割り勘の黒字表示は + だけを ¥ の外側で足して組み立てる
    test('+ を前置しても ¥ の外側に出る', () {
      expect('+${formatYen(1200)}', '+¥1,200');
    });

    // kMaxAmount は DB の CHECK が認める最大値。上限を変えてもここが
    // 取り残されないよう、リテラルではなく形で検証する
    test('上限額でも小数点なしで 3 桁区切りされる', () {
      final s = formatYen(kMaxAmount);

      expect(s.startsWith('¥'), isTrue);
      expect(s, isNot(contains('.')));

      final digits = s.substring(1);
      expect(digits.replaceAll(',', ''), kMaxAmount.toStringAsFixed(0));
      expect(digits.split(',').skip(1).every((g) => g.length == 3), isTrue);
    });
  });

  group('formatRatio', () {
    // 集計画面のカテゴリ別リストと円グラフの扇形ラベルが同じ関数を通る。
    // 桁数を変えると 2 か所の表示が同時に動くので、書式はここで固定する
    test('小数第1位までの % にする', () {
      expect(formatRatio(7500, 10000), '75.0%');
      expect(formatRatio(2500, 10000), '25.0%');
      expect(formatRatio(10000, 10000), '100.0%');
    });

    // この issue の動機。扇形ラベルが出ない比率でもリストには数字が出る
    test('5%未満でもそのまま数字を返す（表示するかは呼び出し側の判断）', () {
      expect(formatRatio(200, 10000), '2.0%');
      expect(formatRatio(1, 10000), '0.0%');
    });

    // 合計を 100% に補正する処理は入れない。円グラフの扇形ラベルも同じ挙動
    test('丸めて合計 100% にならないのは仕様', () {
      final third = formatRatio(1, 3);
      expect(third, '33.3%');
      // 3 等分を 3 つ足しても 100% には届かない。補正する処理は入れない
      final sum = double.parse(third.replaceAll('%', '')) * 3;
      expect(sum, lessThan(100));
      expect(sum, closeTo(99.9, 0.001));
    });

    // 分母 0 で 'NaN%' を描かせない。取引ゼロの月に画面が通る経路
    test('分母が 0 以下のときは - を返す', () {
      expect(formatRatio(0, 0), '-');
      expect(formatRatio(100, 0), '-');
      expect(formatRatio(100, -1), '-');
    });

    // kMaxAmount は DB の CHECK が認める最大値。桁が増えても表現は変わらない
    test('上限額どうしでも 100.0% になる', () {
      expect(formatRatio(kMaxAmount, kMaxAmount), '100.0%');
      expect(formatRatio(kMaxAmount / 2, kMaxAmount), '50.0%');
    });
  });

  group('formatAmountForInput', () {
    // 表示用と取り違えると入力欄に ¥ や桁区切りが入り、
    // AmountInputFormatter が数字以外を落として値が壊れる
    test('¥ も桁区切りも付けない', () {
      expect(formatAmountForInput(1234567), '1234567');
      expect(formatAmountForInput(0), '0');
    });
  });
}
