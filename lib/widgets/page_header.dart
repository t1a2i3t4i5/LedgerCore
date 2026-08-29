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
