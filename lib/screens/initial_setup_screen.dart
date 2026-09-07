import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/member_provider.dart';
import '../providers/startup_provider.dart';
import '../theme/ledger_tokens.dart';
import '../widgets/ledger_card.dart';
import '../widgets/page_header.dart';

/// 名前の上限。DB 側（`Members.name` の `withLength(max: 50)`）と揃える。
const _maxNameLength = 50;

/// 初回起動でだけ出る、2 人の名前を決める画面。
///
/// **スキップも戻る導線も置かない。** メンバーが 0 人のまま通常画面へ進むと、
/// 取引の支払者を選べない画面が出来る。OS のアプリ終了は妨げないので、
/// 抜け道が無いわけではない（終了しても保存前なら次回また出る）。
///
/// 「あなた」は入力時の案内でしかない。DB に自分を表す列は持たず、
/// 登録順にも意味を持たせない（#116 で持たないと決めた属性を持ち込まない）。
class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _myNameCtrl = TextEditingController();
  final _partnerNameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _myNameCtrl.dispose();
    _partnerNameCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return '名前を入力してください';
    if (name.length > _maxNameLength) return '名前は$_maxNameLength文字までです';
    return null;
  }

  Future<void> _save() async {
    // 再描画の前に続けて押されても登録は 1 回だけにする
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // await を跨ぐので、context は先に読んでおく
    final members = context.read<MemberProvider>();
    final startup = context.read<StartupProvider>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _saving = true);
    try {
      await members.createInitialMembers(
        _myNameCtrl.text.trim(),
        _partnerNameCtrl.text.trim(),
      );
    } catch (e) {
      // 入力内容はそのまま残し、同じ画面で再試行できるようにする
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('保存に失敗しました。もう一度お試しください')),
      );
      return;
    }
    // Navigator を積まず、アプリのルートを通常画面へ切り替える。
    // この画面はここで破棄されるので、以降 setState は呼ばない
    await startup.load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeader(title: '2人の名前'),
                const SizedBox(height: 12),
                Text(
                  '一緒に家計簿を使う2人の名前を登録します。'
                  'あとから設定のメンバー管理で変更できます。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                LedgerCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _NameField(
                        label: 'あなたの名前',
                        hintText: '例）たろう',
                        controller: _myNameCtrl,
                        validator: _validateName,
                        enabled: !_saving,
                        textInputAction: TextInputAction.next,
                      ),
                      const Divider(height: 1),
                      _NameField(
                        label: 'もう1人の名前',
                        hintText: '例）はなこ',
                        controller: _partnerNameCtrl,
                        validator: _validateName,
                        enabled: !_saving,
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // 取引入力と同じ形。Scaffold に下部領域を知らせて保存失敗の SnackBar を
      // ボタンの上へ出し、下端に viewInsets を足してキーボードを避ける
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(32, 8, 32, 16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child:
                _saving
                    ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('はじめる'),
          ),
        ),
      ),
    );
  }
}

/// カード内の「ラベルの下に入力欄」の 1 行。
///
/// ラベルを左に置く形（取引入力の `_DetailRow`）は使わない。ここのラベルは
/// 6〜7 文字あり、文字倍率を上げると入力欄の取り分が無くなるため。
class _NameField extends StatelessWidget {
  const _NameField({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.validator,
    required this.enabled,
    required this.textInputAction,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final bool enabled;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: LedgerTokens.subtext),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: controller,
            validator: validator,
            enabled: enabled,
            textInputAction: textInputAction,
            decoration: InputDecoration(
              hintText: hintText,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
