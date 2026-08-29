import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/widgets/page_header.dart';

Future<void> _pumpHeader(
  WidgetTester tester, {
  String title = '取引',
  Widget? leading,
  List<Widget> actions = const [],
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(360, 690);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 690),
            textScaler: TextScaler.linear(textScale),
          ),
          child: PageHeader(title: title, leading: leading, actions: actions),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('headlineMedium のスタイルをそのまま使う', (tester) async {
    const headlineMedium = TextStyle(
      fontFamily: 'TestHeading',
      fontSize: 31,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
    );
    final theme = ThemeData(
      textTheme: const TextTheme(headlineMedium: headlineMedium),
    );

    await _pumpHeader(tester, theme: theme);

    final title = tester.widget<Text>(find.text('取引'));
    final context = tester.element(find.byType(PageHeader));
    expect(title.style, Theme.of(context).textTheme.headlineMedium);
  });

  testWidgets('leading と actions を見出しの左右に表示する', (tester) async {
    await _pumpHeader(
      tester,
      leading: BackButton(onPressed: () {}),
      actions: [TextButton(onPressed: () {}, child: const Text('保存'))],
    );

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('取引'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '保存'), findsOneWidget);

    final leadingX = tester.getCenter(find.byType(BackButton)).dx;
    final titleX = tester.getCenter(find.text('取引')).dx;
    final actionX = tester.getCenter(find.widgetWithText(TextButton, '保存')).dx;
    expect(leadingX, lessThan(titleX));
    expect(titleX, lessThan(actionX));
  });

  testWidgets('幅 360・文字倍率 2.0 で長い見出しとアクションが溢れず縦に伸びる', (tester) async {
    Widget leading() => BackButton(onPressed: () {});
    List<Widget> actions() => [
      TextButton(onPressed: () {}, child: const Text('保存')),
    ];

    await _pumpHeader(
      tester,
      title: '取引を追加',
      leading: leading(),
      actions: actions(),
    );
    final normalHeight = tester.getSize(find.byType(PageHeader)).height;

    await _pumpHeader(
      tester,
      title: '取引を追加',
      leading: leading(),
      actions: actions(),
      textScale: 2,
    );
    final scaledHeight = tester.getSize(find.byType(PageHeader)).height;

    expect(tester.takeException(), isNull);
    expect(scaledHeight, greaterThan(normalHeight));
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('取引を追加'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '保存'), findsOneWidget);
  });
}
