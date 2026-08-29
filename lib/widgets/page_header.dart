import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 画面のコンテンツ先頭に置く大見出し。
///
/// 外側の余白は持たず、各画面のレイアウトに委ねる。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  /// 見出しに表示する文字列。
  final String title;

  /// 見出しの左に置くウィジェット。
  final Widget? leading;

  /// 見出しの右に並べるアクション。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 8),
          Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ],
    );
  }
}

/// push 遷移先で、唯一の戻る導線と大見出しを画面上端に残す Sliver。
///
/// タイトルの1行分と標準の戻るボタンが文字倍率に応じて収まる高さを取り、
/// 不透明な背景ごと固定する。一覧はこの Sliver の下をスクロールする。
class PinnedBackPageHeader extends StatelessWidget {
  const PinnedBackPageHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineMedium!;
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final extent = math.max(kMinInteractiveDimension, painter.height) + 32;
    painter.dispose();

    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedBackPageHeaderDelegate(
        title: title,
        extent: extent,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
    );
  }
}

class _PinnedBackPageHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedBackPageHeaderDelegate({
    required this.title,
    required this.extent,
    required this.backgroundColor,
  });

  final String title;
  final double extent;
  final Color backgroundColor;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: backgroundColor,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: PageHeader(title: title, leading: const BackButton()),
    ),
  );

  @override
  bool shouldRebuild(_PinnedBackPageHeaderDelegate oldDelegate) =>
      title != oldDelegate.title ||
      extent != oldDelegate.extent ||
      backgroundColor != oldDelegate.backgroundColor;
}
