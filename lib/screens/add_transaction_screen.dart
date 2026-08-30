import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction.dart';
import '../providers/category_provider.dart';
import '../providers/member_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/ledger_tokens.dart';
import '../widgets/amount_format.dart';
import '../widgets/ledger_card.dart';
import '../widgets/period_format.dart';

class AddTransactionScreen extends StatefulWidget {
  // 編集時は既存の取引を渡す
  final TransactionView? existing;

  const AddTransactionScreen({super.key, this.existing});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  DateTime _spentAt = DateTime.now();
  int? _selectedCategoryId;
  int? _selectedMemberId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      // DB の CHECK 制約と v3 の移行によって amount は必ず整数なので、
      // 小数部を出さずに「1000」と見せる（整形はフィルターシートと共有）
      _amountCtrl.text = formatAmountForInput(ex.amount);
      _memoCtrl.text = ex.memo ?? '';
      _spentAt = ex.spentAt;
      _selectedCategoryId = ex.categoryId;
      _selectedMemberId = ex.memberId;
    }
    // カテゴリ一覧とメンバー一覧を取得する
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final catProvider = context.read<CategoryProvider>();
      final memberProvider = context.read<MemberProvider>();
      await Future.wait([catProvider.fetch(), memberProvider.fetchMembers()]);
      if (!mounted) return;
      // 新規登録時は先頭メンバーをデフォルト選択
      if (widget.existing == null && _selectedMemberId == null) {
        final members = memberProvider.members;
        if (members.isNotEmpty) {
          setState(() => _selectedMemberId = members.first.id);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('カテゴリを選択してください')));
      return;
    }
    if (_selectedMemberId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登録者を選択してください')));
      return;
    }

    setState(() => _loading = true);
    // pop したあとに使うので、context に触る参照は先に取っておく。
    // ScaffoldMessenger は MaterialApp 側にあるので、この画面が閉じても生きている
    final provider = context.read<TransactionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // 保存先の月が表示中の月と違うと、保存が成功しても一覧にも合計にも
    // 何も現れない。比較のため保存前の表示月を控える
    final shownYear = provider.year;
    final shownMonth = provider.month;
    try {
      final memo = _memoCtrl.text.trim();
      final savedAt = _spentAt;
      final input = TransactionInput(
        memberId: _selectedMemberId!,
        categoryId: _selectedCategoryId!,
        amount: double.parse(_amountCtrl.text.trim()),
        spentAt: savedAt,
        memo: memo.isEmpty ? null : memo,
      );

      if (widget.existing != null) {
        await provider.update(widget.existing!.id, input);
      } else {
        await provider.create(input);
      }

      if (mounted) {
        navigator.pop();
        _showSavedFeedback(
          messenger: messenger,
          provider: provider,
          savedAt: savedAt,
          shownYear: shownYear,
          shownMonth: shownMonth,
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('保存失敗: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 保存が成功したことを SnackBar で知らせる。
  ///
  /// 保存先の月が表示中の月と違うと、一覧にも合計にも何も現れないので
  /// 「保存に失敗した」ようにしか見えない。保存先の月を名指ししたうえで、
  /// その月へ移る導線を添える。自動で移さないのは、閲覧中の月を無断で
  /// 動かさないため（どちらを見続けるかはユーザーが決める）
  void _showSavedFeedback({
    required ScaffoldMessengerState messenger,
    required TransactionProvider provider,
    required DateTime savedAt,
    required int shownYear,
    required int shownMonth,
  }) {
    final inShownMonth =
        savedAt.year == shownYear && savedAt.month == shownMonth;
    // 続けて保存したとき古い SnackBar が残ると、どの保存の結果か分からなくなる
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          inShownMonth
              ? '保存しました'
              : '${formatPeriod(savedAt.year, savedAt.month)}に保存しました',
        ),
        action:
            inShownMonth
                ? null
                : SnackBarAction(
                  label: 'その月を表示',
                  onPressed:
                      () => provider.goToMonth(savedAt.year, savedAt.month),
                ),
        // 取引一覧の FAB は内側の Scaffold にあり、ルートの ScaffoldMessenger が
        // 出す SnackBar では押し上げられない。既定の fixed のままだと
        // 「その月を表示」が FAB にぴたりと重なり、続けてもう 1 件追加しようと
        // した指が月移動を押すことになる。浮かせて FAB の上へ逃がす
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        // アクションを押す間が要るぶん、別月のときは長めに出す
        duration: Duration(seconds: inShownMonth ? 2 : 6),
      ),
    );
  }

  /// 現在の文字倍率で上限額の全桁とカーソルを収める入力欄の幅。
  ///
  /// この内容幅を [FittedBox] の子にし、画面幅の制約を外側へ置くことで、
  /// 狭い画面では入力欄全体を縮小する。内側を画面幅に固定すると
  /// [EditableText] が横スクロールして先頭の桁を隠すため。
  double _amountFieldWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: kMaxAmount.toStringAsFixed(0),
        style: LedgerTokens.amountLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + 8;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    // 既定の日付は「今日」で、一覧が表示している月とは独立している
    // （CLAUDE.md の「追加画面の既定日付は表示月に寄せない」）。
    // ずれたまま保存すると一覧から消えて見えるので、保存前に気づける位置で伝える
    final shown = context.watch<TransactionProvider>();
    final savingToOtherMonth =
        _spentAt.year != shown.year || _spentAt.month != shown.month;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TransactionHeader(
              title: isEdit ? '支出を編集' : '支出を追加',
              onCancel: _loading ? null : () => Navigator.of(context).pop(),
              onSave: _loading ? null : _save,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 金額
                      Text(
                        '金額',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: LedgerTokens.subtext,
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: _amountFieldWidth(context),
                            child: TextFormField(
                              controller: _amountCtrl,
                              // 小数を受け付けないので小数点キーの要らない number に戻す
                              keyboardType: TextInputType.number,
                              inputFormatters: const [AmountInputFormatter()],
                              textAlign: TextAlign.center,
                              style: LedgerTokens.amountLarge,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return '金額を入力してください';
                                }
                                final amount = double.tryParse(v);
                                if (amount == null) return '有効な数値を入力してください';
                                // 支出額なので 0 と負の値は弾く（DB 側の CHECK 制約と同じ条件）
                                if (amount <= 0) return '金額は 0 より大きい値を入力してください';
                                // Infinity は `> 0` を満たすため上限の比較で止める。
                                // 弾かないと合計が `¥∞`、構成比が `NaN%` になって復旧できない
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
                          ),
                        ),
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
                            items:
                                cats
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c.id,
                                        child: Text(c.name),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (v) => setState(() => _selectedCategoryId = v),
                            validator:
                                (v) => v == null ? 'カテゴリを選択してください' : null,
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // 登録者（メンバー）選択
                      Consumer<MemberProvider>(
                        builder: (context, memberProvider, _) {
                          final members = memberProvider.members;
                          return FormField<int>(
                            initialValue: _selectedMemberId,
                            validator:
                                (_) =>
                                    _selectedMemberId == null
                                        ? '登録者を選択してください'
                                        : null,
                            builder: (state) {
                              return InputDecorator(
                                decoration: InputDecoration(
                                  labelText: '登録者',
                                  prefixIcon: const Icon(Icons.person_outline),
                                  border: const OutlineInputBorder(),
                                  errorText: state.errorText,
                                  // チップを並べるため内側の余白を調整
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                ),
                                child:
                                    members.isEmpty
                                        ? Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          child: Text(
                                            'メンバー情報を読み込み中...',
                                            style: TextStyle(
                                              color:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                            ),
                                          ),
                                        )
                                        : Wrap(
                                          spacing: 8,
                                          runSpacing: 0,
                                          children:
                                              members.map((m) {
                                                final selected =
                                                    _selectedMemberId == m.id;
                                                return ChoiceChip(
                                                  label: Text(m.name),
                                                  selected: selected,
                                                  onSelected: (value) {
                                                    if (!value) return;
                                                    setState(
                                                      () =>
                                                          _selectedMemberId =
                                                              m.id,
                                                    );
                                                    state.didChange(m.id);
                                                  },
                                                );
                                              }).toList(),
                                        ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // 内容と日付は、ラベルと値を左右で読める 1 枚のカードにまとめる
                      LedgerCard(
                        padding: EdgeInsets.zero,
                        child: Material(
                          type: MaterialType.transparency,
                          borderRadius: BorderRadius.circular(
                            LedgerTokens.cardRadius,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              _DetailRow(
                                label: '内容',
                                child: TextFormField(
                                  controller: _memoCtrl,
                                  maxLines: 3,
                                  textAlign: TextAlign.end,
                                  decoration: const InputDecoration(
                                    hintText: 'メモ（任意）',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              InkWell(
                                onTap: _loading ? null : _pickDate,
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(
                                    LedgerTokens.cardRadius,
                                  ),
                                ),
                                child: _DetailRow(
                                  label: '日付',
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      helperText:
                                          savingToOtherMonth
                                              ? '表示中の${formatPeriod(shown.year, shown.month)}とは別の月です'
                                              : null,
                                      helperMaxLines: 3,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            DateFormat(
                                              'yyyy年MM月dd日',
                                            ).format(_spentAt),
                                            textAlign: TextAlign.end,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.calendar_today),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: _loading ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                ),
                child:
                    _loading
                        ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('保存する'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 追加・編集の両方で使う 3 分割ヘッダ。
///
/// 各領域を [Expanded] で等分し、文字倍率を上げたときは
/// 各領域内で高さ方向に伸びる。中央の見出しを左右の文字幅で
/// ずらさず、横 overflow も起こさない。
class _TransactionHeader extends StatelessWidget {
  const _TransactionHeader({
    required this.title,
    required this.onCancel,
    required this.onSave,
  });

  final String title;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextButton(
              onPressed: onCancel,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text('キャンセル', textAlign: TextAlign.left),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
          Expanded(
            child: TextButton(
              onPressed: onSave,
              child: const Align(
                alignment: Alignment.centerRight,
                child: Text('保存', textAlign: TextAlign.right),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 入力カード内の「左ラベル / 右に入力値」の 1 行。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}
