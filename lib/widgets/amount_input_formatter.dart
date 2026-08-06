import 'package:flutter/services.dart';

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
/// 小数点は受け付けない。金額の表示は全画面 `NumberFormat('#,###')` で
/// 小数部を出さないため、小数を許すと「保存されるが見えず合計だけ合わない」
/// 状態になる（DB 側の CHECK 制約と揃えている）。
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
