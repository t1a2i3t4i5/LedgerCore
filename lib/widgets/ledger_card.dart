import 'package:flutter/material.dart';

import '../theme/ledger_tokens.dart';

/// LedgerCore の画面で使う、白地・角丸・影付きの共通カード。
class LedgerCard extends StatelessWidget {
  const LedgerCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LedgerTokens.cardRadius),
        boxShadow: const [LedgerTokens.cardShadow],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
