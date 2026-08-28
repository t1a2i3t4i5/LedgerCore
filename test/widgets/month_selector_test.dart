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
    // null を渡すと年だけを表示する年単位の選択になる
    int? month = 7,
    bool todayEnabled = true,
    String? todayTooltip,
    TextStyle? style,
    List<Widget> actions = const [],
    double textScale = 1.0,
    double? width,
  }) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Widget selector = MonthSelector(
      year: year,
      month: month,
      style: style,
      onPrev: () => pressed.add('prev'),
      onNext: () => pressed.add('next'),
      onToday: todayEnabled ? () => pressed.add('today') : null,
      todayTooltip: todayTooltip ?? '今月に戻る',
      actions: actions,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child:
                width == null
                    ? selector
                    : SizedBox(width: width, child: selector),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 年月が 1 行に収まらず省略されたか。
  /// [find.text] は畳まれた [Text] にもマッチするので描画側に訊く
  bool isEllipsized(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  /// 「今月に戻る」ボタンが押せる状態か
  bool todayIsEnabled(WidgetTester tester) =>
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.text('今月'),
              matching: find.byType(IconButton),
            ),
          )
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

    await tester.tap(find.text('今月'));
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
    double xOfIcon(IconData icon) => tester.getCenter(find.byIcon(icon)).dx;
    final todayX = tester.getCenter(find.text('今月')).dx;
    expect(xOfIcon(Icons.chevron_left), lessThan(xOfIcon(Icons.chevron_right)));
    expect(xOfIcon(Icons.chevron_right), lessThan(todayX));
    expect(todayX, lessThan(xOfIcon(Icons.filter_list)));
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
    expect(isEllipsized(tester, '9999年12月'), isFalse);
  });

  testWidgets('幅が足りなければ年月は 1 行のまま省略される', (tester) async {
    // 上の isFalse の裏を取る対照ケース。maxLines を外すと
    // didExceedMaxLines は常に false を返すので、isFalse だけでは
    // 省略の契約を何も守れない（docs/testing.md）
    await pump(
      tester,
      year: 9999,
      month: 12,
      actions: [filterButton()],
      width: 200,
    );

    expect(tester.takeException(), isNull);
    expect(isEllipsized(tester, '9999年12月'), isTrue);
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

  group('年単位で使うとき', () {
    // 集計画面の年モードがこの形で使う
    testWidgets('month が null なら年だけを表示する', (tester) async {
      await pump(tester, month: null);

      expect(find.text('2026年'), findsOneWidget);
      expect(find.text('2026年7月'), findsNothing);
    });

    // 矢印の意味は呼び出し側が決める（年モードでは年送り）。
    // ウィジェット側はコールバックを呼ぶだけ、という契約を固定する
    testWidgets('年表示でも矢印は同じコールバックを呼ぶ', (tester) async {
      await pump(tester, month: null);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.tap(find.text('今月'));

      expect(pressed, ['prev', 'next', 'today']);
    });

    testWidgets('tooltip を差し替えられる（既定は今月に戻る）', (tester) async {
      await pump(tester);
      expect(find.byTooltip('今月に戻る'), findsOneWidget);

      await pump(tester, month: null, todayTooltip: '今年に戻る');
      expect(find.byTooltip('今年に戻る'), findsOneWidget);
      expect(find.byTooltip('今月に戻る'), findsNothing);
    });

    // 年表示は月表示より短いので、月が収まる幅なら必ず収まる。
    // 対照の isTrue ケースは月表示側（'9999年12月' を幅 200）に既にある
    testWidgets('幅 360 で桁が最大の年でも畳まれない', (tester) async {
      await pump(
        tester,
        year: 9999,
        month: null,
        style: const TextStyle(fontSize: 16),
        actions: [filterButton()],
      );

      expect(tester.takeException(), isNull);
      expect(isEllipsized(tester, '9999年'), isFalse);
    });
  });
}
