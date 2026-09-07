import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/startup_provider.dart';
import 'initial_setup_screen.dart';
import 'main_screen.dart';

/// アプリのルート。DB の状態を読んで、初期設定と通常画面を出し分ける。
///
/// 画面を push せずルートの子を差し替えるので、初期設定から通常画面へ移った
/// あとに戻る操作で初期設定へ帰る経路が残らない。
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<StartupProvider>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (context.watch<StartupProvider>().phase) {
      case StartupPhase.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case StartupPhase.setup:
        return const InitialSetupScreen();
      case StartupPhase.ready:
        return const MainScreen();
      case StartupPhase.inconsistent:
        // 復旧機能は持たない。**初期設定へは送らない** — 既存の取引と
        // 無関係なメンバーを足すことになり、支払者が静かに書き換わる
        return const _StartupError(
          message:
              'メンバーが登録されていないのに取引が残っています。\n'
              'データの状態を確認できないため、初期設定は行いません。',
        );
      case StartupPhase.failed:
        return _StartupError(
          message: 'データの読み込みに失敗しました。',
          onRetry: () => context.read<StartupProvider>().load(),
        );
    }
  }
}

/// 起動できなかったことを伝える画面。[onRetry] があるときだけ再試行を出す。
class _StartupError extends StatelessWidget {
  const _StartupError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onRetry, child: const Text('再試行')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
