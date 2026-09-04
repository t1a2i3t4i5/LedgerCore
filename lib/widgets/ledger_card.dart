import 'package:flutter/material.dart';

import '../theme/ledger_tokens.dart';

/// LedgerCore の共通カードの装飾。
///
/// [LedgerCard] と、一覧を 1 枚のカードに見せる `DecoratedSliver` の両方が
/// これを使う。カードの見た目の出所を 1 か所に保つため、白地・角丸・影を
/// 画面側で組み立て直さない。
BoxDecoration ledgerCardDecoration(BuildContext context) => BoxDecoration(
  color: Theme.of(context).colorScheme.surfaceContainerLow,
  borderRadius: BorderRadius.circular(LedgerTokens.cardRadius),
  boxShadow: const [LedgerTokens.cardShadow],
);

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
      decoration: ledgerCardDecoration(context),
      child: Padding(padding: padding, child: child),
    );
  }
}
