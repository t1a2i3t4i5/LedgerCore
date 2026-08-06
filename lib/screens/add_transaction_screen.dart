import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction.dart';
import '../providers/category_provider.dart';
import '../providers/member_provider.dart';
import '../providers/transaction_provider.dart';

class AddTransactionScreen extends StatefulWidget {
  // 編集時は既存の取引を渡す
  final TransactionResponse? existing;

  const AddTransactionScreen({super.key, this.existing});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

/// 金額欄に入力できる最大文字数。
///
/// 上限が無いと桁を打ち続けるだけで `double` が `Infinity` に飽和する。
///
/// 桁数は [kMaxAmount] から導出する。リテラルで持つと、上限を変えたときに
/// ここだけ取り残されて「上限まで打てない」か「打てるのに保存で落ちる」に
/// なる（値の上限と入力欄の桁数は必ず同じ源から採る）。
final _maxAmountLength = kMaxAmount.toStringAsFixed(0).length;

/// 金額欄の入力フォーマッタ。
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
class _AmountInputFormatter extends TextInputFormatter {
  const _AmountInputFormatter();

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
    LengthLimitingTextInputFormatter(_maxAmountLength),
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

/// 金額をテキスト欄の初期値にする。
///
/// DB の CHECK 制約と v3 の移行によって amount は必ず整数なので、
/// 小数部を出さずに「1000」と見せる。
String _formatAmount(double amount) => amount.toStringAsFixed(0);

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  DateTime _spentAt = DateTime.now();
  int? _selectedCategoryId;
  int? _selectedUserId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _amountCtrl.text = _formatAmount(ex.amount);
      _memoCtrl.text = ex.memo ?? '';
      _spentAt = ex.spentAt;
      _selectedCategoryId = ex.categoryId;
      _selectedUserId = ex.userId;
    }
    // カテゴリ一覧とメンバー一覧を取得する
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final catProvider = context.read<CategoryProvider>();
      final memberProvider = context.read<MemberProvider>();
      await Future.wait([
        catProvider.fetch(),
        memberProvider.fetchMembers(),
      ]);
      if (!mounted) return;
      // 新規登録時は先頭メンバーをデフォルト選択
      if (widget.existing == null && _selectedUserId == null) {
        final members = memberProvider.members;
        if (members.isNotEmpty) {
          setState(() => _selectedUserId = members.first.id);
        }
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _spentAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _spentAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カテゴリを選択してください')),
      );
      return;
    }
    if (_selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登録者を選択してください')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final memo = _memoCtrl.text.trim();
      final request = TransactionRequest(
        userId: _selectedUserId!,
        categoryId: _selectedCategoryId!,
        amount: double.parse(_amountCtrl.text.trim()),
        spentAt: _spentAt,
        memo: memo.isEmpty ? null : memo,
      );

      final provider = context.read<TransactionProvider>();
      if (widget.existing != null) {
        await provider.update(widget.existing!.id, request);
      } else {
        await provider.create(request);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失敗: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '取引を編集' : '取引を追加'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 金額
                TextFormField(
                  controller: _amountCtrl,
                  // 小数を受け付けないので小数点キーの要らない number に戻す
                  keyboardType: TextInputType.number,
                  inputFormatters: const [_AmountInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: '金額',
                    prefixIcon: Icon(Icons.currency_yen),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '金額を入力してください';
                    final amount = double.tryParse(v);
                    if (amount == null) return '有効な数値を入力してください';
                    // 支出額なので 0 と負の値は弾く（DB 側の CHECK 制約と同じ条件）
                    if (amount <= 0) return '金額は 0 より大きい値を入力してください';
                    // Infinity は `> 0` を満たすため上限の比較で止める。
                    // 弾かないと合計と円グラフが NaN になって復旧できない
                    if (!amount.isFinite || amount > kMaxAmount) {
                      return '金額が大きすぎます';
                    }
                    // フォーマッタが小数点を通さないので実質到達しないが、
                    // コントローラへの直接代入も含めて DB の CHECK と揃える
                    if (amount != amount.roundToDouble()) {
                      return '金額は整数で入力してください';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // カテゴリ選択
                Consumer<CategoryProvider>(
                  builder: (context, catProvider, _) {
                    final cats = catProvider.categories;
                    return DropdownButtonFormField<int>(
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'カテゴリ',
                        prefixIcon: Icon(Icons.label_outline),
                        border: OutlineInputBorder(),
                      ),
                      items: cats
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                      validator: (v) => v == null ? 'カテゴリを選択してください' : null,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // 登録者（メンバー）選択 - ラジオボタン
                Consumer<MemberProvider>(
                  builder: (context, memberProvider, _) {
                    final members = memberProvider.members;
                    return FormField<int>(
                      initialValue: _selectedUserId,
                      validator: (_) => _selectedUserId == null
                          ? '登録者を選択してください'
                          : null,
                      builder: (state) {
                        return InputDecorator(
                          decoration: InputDecoration(
                            labelText: '登録者',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                            errorText: state.errorText,
                            // ラジオボタンを並べるため内側の余白を調整
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                          ),
                          child: members.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'メンバー情報を読み込み中...',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 0,
                                  children: members.map((m) {
                                    return InkWell(
                                      onTap: () {
                                        setState(() => _selectedUserId = m.id);
                                        state.didChange(m.id);
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Radio<int>(
                                            value: m.id,
                                            // ignore: deprecated_member_use
                                            groupValue: _selectedUserId,
                                            // ignore: deprecated_member_use
                                            onChanged: (v) {
                                              setState(
                                                () => _selectedUserId = v,
                                              );
                                              state.didChange(v);
                                            },
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 4,
                                            ),
                                            child: Text(m.name),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),

                // 日付選択
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '日付',
                      prefixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      DateFormat('yyyy年MM月dd日').format(_spentAt),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // メモ
                TextFormField(
                  controller: _memoCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'メモ（任意）',
                    prefixIcon: Icon(Icons.notes),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
