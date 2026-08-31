import 'package:flutter/material.dart';

import '../models/split.dart';
import '../theme/ledger_tokens.dart';
import 'amount_format.dart';
import 'chart_palette.dart';

/// 月の割り勘結果をホームに表示する。計算とデータ取得は行わない。
class SettlementSummaryCard extends StatelessWidget {
  const SettlementSummaryCard({super.key, required this.split, this.onTap});

  final SplitResult split;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 差額は整数円に丸めて出す。丸めて ¥0 になる人を支払う側に数えると
    // 「¥0 を支払う」行が並ぶ（3人で 1000 円を等分すると各自 -0.33 になる）。
    // 丸めの規則を書き写さず、表示に使う formatYen() 自身に判定させる。
    //
    // 篩を掛けるのは支払う側だけ。受け取り側にも掛けると、3人で 2000 円を
    // 等分した +0.33 / +0.33 / -0.67 で受け取り手がいなくなり、¥1 払う人が
    // いるのに「精算不要」になって割り勘タブの精算文と食い違う。
    final creditors = split.members.where((member) => member.balance > 0);
    final debtors = split.members.where(
      (member) =>
          member.balance < 0 && formatYen(member.balance.abs()) != formatYen(0),
    );
    final needsSettlement = creditors.isNotEmpty && debtors.isNotEmpty;
    final pair = split.members.length == 2 && needsSettlement;
    final avatarMembers =
        pair
            ? [debtors.single, creditors.single]
            : split.members.take(3).toList();
    final action =
        onTap == null
            ? null
            : FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: Text(needsSettlement ? '精算する' : '割り勘を見る'),
            );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (split.members.length < 2)
          Text(
            split.members.isEmpty ? 'メンバーを登録すると精算できます' : '精算には2人以上のメンバーが必要です',
          )
        else if (!needsSettlement)
          const Text('精算不要')
        else if (pair)
          _payment(
            context,
            '${debtors.single.memberName} → ${creditors.single.memberName} に',
            debtors.single.balance.abs(),
          )
        else ...[
          const Text('精算に必要な支払い'),
          // 3人以上の送金先は既存の計算結果に無い。新たに割り当てず、
          // 各メンバーの不足額を省略せずに並べる。
          for (final debtor in debtors) ...[
            const SizedBox(height: 8),
            _payment(context, '${debtor.memberName} は', debtor.balance.abs()),
          ],
        ],
      ],
    );

    return Material(
      color: LedgerTokens.settlementSurface,
      borderRadius: BorderRadius.circular(LedgerTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      // カード全体はタップ領域にしない。移動できるのはボタンだけで、
      // 本文や余白を押しても割り勘タブへ飛ばない。
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 実際の書体と文字倍率で測り、アイコン・本文・ボタンが
            // 収まるときだけ横並びにする。長い名前や上限額は縦へ逃がす。
            final textTheme = Theme.of(context).textTheme;
            final inline =
                pair &&
                60 +
                        12 +
                        _pairWidth(context, debtors.single, creditors.single) +
                        (action == null
                            ? 0
                            : 12 +
                                32 +
                                _textWidth(
                                  context,
                                  '精算する',
                                  textTheme.labelLarge!,
                                )) <=
                    constraints.maxWidth;
            if (inline) {
              return Row(
                children: [
                  _MemberAvatars(members: avatarMembers),
                  const SizedBox(width: 12),
                  Expanded(child: content),
                  if (action != null) ...[const SizedBox(width: 12), action],
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (avatarMembers.isNotEmpty) ...[
                  _MemberAvatars(members: avatarMembers),
                  const SizedBox(height: 12),
                ],
                content,
                if (action != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _payment(BuildContext context, String label, double amount) {
    // 名前と金額を2段に分け、各段は文字倍率に応じてさらに折り返せる。
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label\n'),
          TextSpan(
            text: formatYen(amount),
            style: LedgerTokens.amountRow.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: LedgerTokens.bodyMuted),
    );
  }

  double _pairWidth(
    BuildContext context,
    MemberBalance from,
    MemberBalance to,
  ) {
    final style = Theme.of(context).textTheme.bodyMedium!;
    final labelWidth = _textWidth(
      context,
      '${from.memberName} → ${to.memberName} に',
      style,
    );
    final amountWidth = _textWidth(
      context,
      formatYen(from.balance.abs()),
      style.merge(LedgerTokens.amountRow),
    );
    return labelWidth > amountWidth ? labelWidth : amountWidth;
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// 送金元を左、送金先を右に重ねる。名前は本文にあるため読み上げは重ねない。
class _MemberAvatars extends StatelessWidget {
  const _MemberAvatars({required this.members});

  final List<MemberBalance> members;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 36 + 24.0 * (members.length - 1),
        height: 36,
        child: Stack(
          children: [
            for (final (index, member) in members.indexed)
              PositionedDirectional(
                start: index * 24.0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: LedgerTokens.settlementSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: memberColor(member.memberId),
                      child: Text(
                        member.memberName.isEmpty
                            ? '?'
                            : member.memberName.characters.first,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: labelColorOn(memberColor(member.memberId)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
