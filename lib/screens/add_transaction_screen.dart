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

/// 全角数字・全角ピリオドを半角に直したうえで、数字と小数点以外を落とす。
///
/// 単に落とすだけだと、日本語 IME で全角のまま打ったときに文字が消えるだけで
/// 理由が分からない。半角に直してから絞ることで全角入力もそのまま通す。
final _amountInputFormatters = <TextInputFormatter>[
  TextInputFormatter.withFunction((oldValue, newValue) {
    // 全角→半角は 1 文字 1 文字の置換なので、文字数もカーソル位置も変わらない
    final normalized = newValue.text.replaceAllMapped(
      RegExp(r'[０-９．]'),
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
    );
    return normalized == newValue.text
        ? newValue
        : newValue.copyWith(text: normalized);
  }),
  // マイナス記号やその他の記号は入力自体を受け付けない
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
];

/// 金額をテキスト欄の初期値にする。
///
/// 整数なら小数部を出さず「1000」と見せる。`toStringAsFixed(0)` で丸めてしまうと、
/// 小数を含む取引を編集画面で開いて保存し直しただけで値が変わってしまう。
String _formatAmount(double amount) =>
    amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : '$amount';

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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _amountInputFormatters,
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
