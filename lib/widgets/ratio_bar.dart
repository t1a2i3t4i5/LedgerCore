import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ledger_tokens.dart';

/// 金額が合計に占める割合を、横帯の長さで表す。
class RatioBar extends StatelessWidget {
  const RatioBar({
    super.key,
    required this.amount,
    required this.total,
    required this.color,
    this.height = 8,
  });

  final double amount;
  final double total;
  final Color color;
  final double height;

  static const double _minimumVisibleWidth = 2;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rawRatio = total <= 0 ? 0.0 : amount / total;
          final ratio = rawRatio.clamp(0.0, 1.0);
          final widthFactor =
              ratio <= 0 || constraints.maxWidth <= 0
                  ? 0.0
                  : math.max(
                    ratio,
                    math.min(1.0, _minimumVisibleWidth / constraints.maxWidth),
                  );

          return ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: ColoredBox(
              color: LedgerTokens.barTrack,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: widthFactor,
                  heightFactor: 1,
                  child: ColoredBox(color: color),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
