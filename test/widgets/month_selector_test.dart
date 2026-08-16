import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/widgets/month_selector.dart';

/// 月選択 UI（[MonthSelector]）を DB も Provider も組み立てずに単体で見る。
///
/// 3 画面ぶんの月送りは month_navigation_test.dart が Provider 込みで見ているが、
/// あちらは「Provider の月が動いたか」しか判定できない。矢印とコールバックの
/// 対応そのものは、引数で渡したコールバックが呼ばれたかを直接見るここで塞ぐ。
void main() {
  /// 押されたコールバックの名前を記録する
  late List<String> pressed;

  setUp(() => pressed = []);

  Future<void> pump(
    WidgetTester tester, {
    int year = 2026,
    int month = 7,
    bool todayEnabled = true,
    TextStyle? style,
    List<Widget> actions = const [],
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final selector = MonthSelector(
      year: year,
      month: month,
      style: style,
      onPrev: () => pressed.add('prev'),
      onNext: () => pressed.add('next'),
      onToday: todayEnabled ? () => pressed.add('today') : null,
      actions: actions,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: selector,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 「今月に戻る」ボタンが押せる状態か
  bool todayIsEnabled(WidgetTester tester) =>
      tester
          .widget<IconButton>(find.ancestor(
            of: find.byIcon(Icons.today),
            matching: find.byType(IconButton),
          ))
          .onPressed !=
      null;

  /// 取引一覧が右端に載せているのと同じフィルターボタン
  Widget filterButton() => IconButton(
        tooltip: 'ソート・フィルター',
        onPressed: () {},
        icon: const Badge(
          isLabelVisible: true,
          label: Text('3'),
          child: Icon(Icons.filter_list),
        ),
      );

  testWidgets('年月を「2026年7月」の書式で出す', (tester) async {
    await pump(tester, year: 2026, month: 7);

    expect(find.text('2026年7月'), findsOneWidget);
  });

  testWidgets('左の矢印は onPrev、右の矢印は onNext を呼ぶ', (tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(pressed, ['prev']);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(pressed, ['prev', 'next']);
  });

  testWidgets('「今月に戻る」は onToday を呼ぶ', (tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.today));
    await tester.pumpAndSettle();

    expect(pressed, ['today']);
  });

  testWidgets('onToday が null なら「今月に戻る」は押せない', (tester) async {
    await pump(tester, todayEnabled: false);

    expect(todayIsEnabled(tester), isFalse);
  });

  testWidgets('onToday を渡せば「今月に戻る」は押せる', (tester) async {
    await pump(tester, todayEnabled: true);

    expect(todayIsEnabled(tester), isTrue);
  });

  testWidgets('actions は右端に並び、押せる', (tester) async {
    await pump(tester, actions: [filterButton()]);

    expect(find.byIcon(Icons.filter_list), findsOneWidget);

    // 左から 前月 → 翌月 → 今月に戻る → actions の順に並ぶ
    double xOf(IconData icon) => tester.getCenter(find.byIcon(icon)).dx;
    expect(xOf(Icons.chevron_left), lessThan(xOf(Icons.chevron_right)));
    expect(xOf(Icons.chevron_right), lessThan(xOf(Icons.today)));
    expect(xOf(Icons.today), lessThan(xOf(Icons.filter_list)));
  });

  testWidgets('幅 360 で、桁が最大の年月に actions を足しても年月が畳まれない', (tester) async {
    // 取引一覧と同じ条件（titleMedium + フィルターボタン）に、年月の桁を最大まで
    // 伸ばしたもの。ellipsis は例外を出さず find.text() も通ってしまうので、
    // 畳まれたかどうかは RenderParagraph に直接聞く
    await pump(
      tester,
      year: 9999,
      month: 12,
      style: const TextStyle(fontSize: 16),
      actions: [filterButton()],
    );

    expect(tester.takeException(), isNull);
    final paragraph =
        tester.renderObject<RenderParagraph>(find.text('9999年12月'));
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('端末の文字サイズを 2 倍にしてもレイアウトが破綻しない', (tester) async {
    // 年月を Flexible + ellipsis で包まずに素の Text で置くと、ここで Row が
    // 溢れて RenderFlex overflow になる。畳んででも崩さない側を選んでいる
    await pump(
      tester,
      year: 9999,
      month: 12,
      style: const TextStyle(fontSize: 16),
      actions: [filterButton()],
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
  });
}
