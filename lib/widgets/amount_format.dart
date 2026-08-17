import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';

/// 金額欄に入力できる最大文字数。
///
/// 上限が無いと桁を打ち続けるだけで `double` が `Infinity` に飽和する。
///
/// 桁数は [kMaxAmount] から導出する。リテラルで持つと、上限を変えたときに
/// ここだけ取り残されて「上限まで打てない」か「打てるのに保存で落ちる」に
/// なる（値の上限と入力欄の桁数は必ず同じ源から採る）。
///
/// テストやヒント文言もこの値を参照できるよう公開する。
final maxAmountInputLength = kMaxAmount.toStringAsFixed(0).length;

/// 保持している金額を入力欄の初期値にする。
///
/// [AmountInputFormatter] が受け付けるのは整数だけなので、小数部は出さない。
/// 入力の受け付け方だけを共有して復元の整形を各画面に散らすと、片方だけ桁区切りを
/// 付けるといったズレが起きるので、対で同じ場所に置く。
String formatAmountForInput(double amount) => amount.toStringAsFixed(0);

/// 画面に出す金額の整形。桁区切りを入れ、**小数部は出さない**。
///
/// 小数部を出さないことは見た目の都合ではなく、DB の CHECK 制約
/// （`db/database.dart` の `Transactions.amount`）が金額を整数に限っている
/// 根拠そのもの。`#,##0.##` のような形に変えると「整数しか保存できないのは
/// 全画面が小数を出さないから」という前提が静かに崩れるので、変えるときは
/// CHECK 制約と移行の丸め方まで一緒に見直す。
///
/// 丸めは half away from zero で、移行で使う SQLite の `ROUND` と同じ
/// （`1234.5` はどちらも `1,235`）。割り勘の `fairShare` は「合計 ÷ 人数」の
/// 導出値で小数が残るが、表示上はこの整形で丸める。
final _displayFormat = NumberFormat('#,###', 'ja_JP');

/// 金額を `¥1,234` の形にする。
///
/// 画面に金額を出すときは必ずこれを使い、`NumberFormat` を各画面で組み立て直さない。
/// 通貨記号まで含めているのは、記号だけ 1 か所で落ちる事故を防ぐため
/// （`lib/` に「記号なしで数値だけ出す」用途は無い）。
///
/// 符号を前置したいときは `'+${formatYen(x)}'` のように外側で足す
/// （割り勘画面の黒字表示がこの形。負の値は `#,###` 自身が `¥-1,000` と出す）。
String formatYen(double amount) => '¥${_displayFormat.format(amount)}';

/// 全体に占める割合を `35.2%` の形にする。
///
/// 現在の呼び出しは集計画面のカテゴリ別リスト 1 か所だけだが、`toStringAsFixed`
/// を画面に書き戻さない。ここに置くのは、**同じ行に並ぶ金額と % の書式が対で
/// 決まる**ため（`trailing` は [formatYen] の結果とこの結果を縦に積む）。
/// 構成比を出す表示が再び増えたとき、桁が画面ごとに食い違うのを防ぐ意味もある。
///
/// **丸めて合計 100% にならないのは仕様。** 3 等分なら 33.3% × 3 = 99.9% に
/// なるが、補正はしない。
String formatRatio(double amount, double total) {
  // 金額は正の整数のみなので byCategory が空でなければ total > 0 だが、
  // 分母 0 で 'NaN%' を描かないよう明示的に逃がす
  if (total <= 0) return '-';
  return '${(amount / total * 100).toStringAsFixed(1)}%';
}

/// 軸ラベルで使う単位。大きい順に見て、最初に届いたものを使う。
const _axisUnits = <(double, String)>[
  (1000000000000.0, '兆'),
  (100000000.0, '億'),
  (10000.0, '万'),
];

/// **グラフの軸ラベル専用**の圧縮表記。`¥1兆` `¥5000億` `¥12.5万` `¥800` の形。
///
/// [formatYen] をそのまま軸に使うと、[kMaxAmount] が `¥999,999,999,999` の
/// 15 文字になり、360px 幅の 3 分の 1 以上を Y 軸が占めてグラフ本体が潰れる。
/// この値は DB の CHECK 制約が現に許すので「そんな金額は入らない」では逃げられない。
///
/// **取引金額の表示には使わないこと。** 丸めるので `¥12.5万` は 125,000 円とは
/// 限らない。画面に出す実額は必ず [formatYen] を通す — 小数部を出さないことが
/// DB の整数 CHECK 制約の根拠になっており、ここはその唯一の例外にあたる。
/// 例外だと分かるよう、丸めた概数には必ず単位を付けて返す。
///
/// 小数第 1 位までで足りるのは、呼び出し側（`widgets/period_bar_chart.dart`）が
/// 目盛りを 1/2/5 × 10^n の倍数に丸めてから渡すため。目盛り幅は最大値の
/// 4 分の 1 以上になるので、単位に直しても 0.2 刻みより細かくならない。
String formatYenAxis(double amount) {
  final abs = amount.abs();
  for (final (scale, suffix) in _axisUnits) {
    if (abs < scale) continue;
    final scaled = (amount / scale).toStringAsFixed(1);
    // '1.0兆' ではなく '1兆'。桁を詰めるための関数なので末尾の .0 は落とす
    final trimmed =
        scaled.endsWith('.0') ? scaled.substring(0, scaled.length - 2) : scaled;
    return '¥$trimmed$suffix';
  }
  // 万に届かない額は圧縮の余地が無いので、通常の表示と同じ形にする
  return formatYen(amount);
}

/// 金額欄の入力フォーマッタ。
///
/// 取引の追加・編集画面とフィルターシートの金額欄が共有する。片方だけ挙動が
/// 違うと、同じアプリ内で「追加画面では全角がそのまま通るのに、フィルターでは
/// 理由の分からないエラーになる」といった食い違いが出る。
///
/// **IME の変換確定前（composing 中）は一切書き換えない。** Flutter は
/// `TextInputFormatter` について composing 中の本文書き換えを禁じており
/// （`services/text_formatter.dart`）、破ると IME 側のバッファと食い違って
/// 二重入力や巻き戻りを起こす。実際、確定前に「１２３」を送ると本文だけ
/// 「123」に書き換わり composing 範囲は残ったままになる。
///
/// 確定後の値は「全角→半角の正規化 → 数字以外の除去 → 桁数制限」の
/// 順で整える。正規化を先に置くのは、単に全角を落とすだけだと日本語 IME で
/// 全角のまま打ったときに文字が消えて理由が分からないため。
///
/// 小数点は受け付けない。金額の表示は [formatYen] が小数部を出さないため、
/// 小数を許すと「保存されるが見えず合計だけ合わない」状態になる
/// （DB 側の CHECK 制約と揃えている）。
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  static final _steps = <TextInputFormatter>[
    TextInputFormatter.withFunction((oldValue, newValue) {
      // 全角→半角は 1 文字 1 文字の置換なので、文字数もカーソル位置も変わらない
      final normalized = newValue.text.replaceAllMapped(
        RegExp(r'[０-９]'),
        (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
      );
      return normalized == newValue.text
          ? newValue
          : newValue.copyWith(text: normalized);
    }),
    // 小数点・マイナス記号・その他の記号は入力自体を受け付けない
    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
    LengthLimitingTextInputFormatter(maxAmountInputLength),
  ];

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    // EditableText 自身と同じく、各段に同じ oldValue を渡して畳み込む
    return _steps.fold(
      newValue,
      (value, step) => step.formatEditUpdate(oldValue, value),
    );
  }
}
