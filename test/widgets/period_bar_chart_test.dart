import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
// RenderParagraph は material には無い
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/models/summary.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:ledger_app/widgets/period_bar_chart.dart';
import 'package:ledger_app/widgets/period_format.dart';

/// fl_chart 1.x では**軸ラベルは Canvas 直描きではなく本物のウィジェット**
/// （`side_titles_widget.dart` が `getTitlesWidget` の返り値をツリーに載せる）
/// なので、`find.text()` で拾えるし `getRect()` で位置も測れる。
/// 一方で**ツールチップの文字は今も Canvas 直描き**なので `find.text()` では
/// 拾えない。そちらは `getTooltipItem` を直接呼んで確かめる。
///
/// 棒の値・色・maxY といったデータは `BarChart.data` に対して検証する。
/// グラフははみ出しても例外も overflow の縞模様も出さず静かに切れるので、
/// `takeException()` だけでは崩れを捕まえられない（円グラフで学んだ型）。

/// アプリ本体と同じテーマ。棒の色は ColorScheme から採るので、
/// 既定テーマのまま測ると production と別の色を見ることになる
final _theme = ledgerTheme;

PeriodTotal _month(int month, double total) =>
    PeriodTotal(year: 2026, month: month, total: total);

PeriodTotal _year(int year, double total) =>
    PeriodTotal(year: year, total: total);

/// 1〜12 月ぶんの [PeriodTotal]。`totals` に渡した値がそのまま各月になる。
List<PeriodTotal> _twelveMonths(List<double> totals) => [
  for (var i = 0; i < 12; i++) _month(i + 1, totals[i]),
];

Future<void> _pump(
  WidgetTester tester,
  List<PeriodTotal> items, {
  // 幅を絞ると軸ラベルが畳まれる。省略時は実機相当の 360px
  double? width,
  // 端末の文字サイズ設定。1.0 以外を通すケースを必ず 1 本以上置く
  double textScale = 1.0,
  double? height,
}) async {
  tester.view.physicalSize = const Size(360, 690);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final chart =
      height == null
          ? PeriodBarChart(items: items)
          : PeriodBarChart(items: items, height: height);

  await tester.pumpWidget(
    MaterialApp(
      theme: _theme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          // 集計画面と同じく ListView の子として置く。ListView の子は高さ制約が
          // 非有界なので、ウィジェットが自分で高さを持てていないとここで落ちる
          child: ListView(
            children: [
              if (width == null)
                chart
              else
                Row(children: [SizedBox(width: width, child: chart)]),
            ],
          ),
        ),
      ),
    ),
  );
  // BarChart は暗黙アニメーションを持つので落ち着かせる
  await tester.pumpAndSettle();
}

BarChartData _data(WidgetTester tester) =>
    tester.widget<BarChart>(find.byType(BarChart)).data;

bool _isEllipsized(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

/// 棒の高さ（入力どおりの合計額）を左から並べる。
List<double> _rodValues(WidgetTester tester) =>
    _data(tester).barGroups.map((g) => g.barRods.single.toY).toList();

/// 実際に描かれた X 軸ラベルの矩形を左から順に返す。
/// 間引かれたラベルはツリーに無いので、拾えたものだけが対象になる。
List<Rect> _visibleXLabelRects(WidgetTester tester, List<PeriodTotal> items) {
  final rects = <Rect>[];
  for (final item in items) {
    final finder = find.text(formatPeriodShort(item.year, item.month));
    if (finder.evaluate().isEmpty) continue;
    rects.add(tester.getRect(finder));
  }
  return rects..sort((a, b) => a.left.compareTo(b.left));
}

/// 描かれた X 軸ラベルが隣と重なっていないことと、**間引かれ過ぎていない**
/// ことの両方を見る。
///
/// 重なりだけを見ると、ラベルが減るほど通りやすくなるので「12 本のうち 2 本
/// しか出ていない」図が最も安全な実装ということになってしまう。読める下限を
/// [minVisible] で押さえる。
void _expectLabelsReadable(
  WidgetTester tester,
  List<PeriodTotal> items, {
  required int minVisible,
}) {
  final rects = _visibleXLabelRects(tester, items);

  expect(
    rects.length,
    greaterThanOrEqualTo(minVisible),
    reason: '${items.length} 件に対しラベルが ${rects.length} 本しか出ていない',
  );
  for (var i = 1; i < rects.length; i++) {
    expect(
      rects[i - 1].right,
      lessThanOrEqualTo(rects[i].left),
      reason: '${i - 1} 番目と $i 番目のラベルが重なっている',
    );
  }
}

void main() {
  group('空の表示', () {
    testWidgets('空リストのときは「データがありません」を出しグラフを描かない', (tester) async {
      await _pump(tester, const []);

      expect(find.text('データがありません'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    // 取引ゼロの月を含む年は珍しくない。描くと高さ 0 の棒が並ぶだけの図になる
    testWidgets('全件 0 のときもグラフを描かない', (tester) async {
      await _pump(tester, _twelveMonths(List.filled(12, 0)));

      expect(find.text('データがありません'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    // 1 件でも 0 より大きければ描く。ここが逆になると「1 月しか使っていない年」の
    // グラフが丸ごと消える
    testWidgets('1 件でも 0 より大きければ描く', (tester) async {
      await _pump(tester, _twelveMonths([100, ...List.filled(11, 0)]));

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('データがありません'), findsNothing);
    });
  });

  group('棒の並び', () {
    // 受け入れ条件「年モードで、取引のない月も 0 として X 軸に並ぶ」。
    // 0 の月を間引くと 12 本の軸が欠けて、隣り合う月が実際より近く見える
    testWidgets('12 件渡すと 0 の月も含めて 12 本になる', (tester) async {
      final totals = <double>[
        1000,
        0,
        3000,
        0,
        0,
        600,
        700,
        800,
        0,
        1000,
        1100,
        1200,
      ];
      await _pump(tester, _twelveMonths(totals));

      final groups = _data(tester).barGroups;
      expect(groups.length, 12);
      expect(groups.map((g) => g.x), List.generate(12, (i) => i));
      expect(_rodValues(tester), totals);
      // 0 の月も rod 自体は残る（棒が消えるだけで軸には並ぶ）
      expect(groups[1].barRods.length, 1);
    });

    // 受け入れ条件「全期間モードで、取引のある年だけが昇順に並ぶ」。
    // 並べ替えはデータ層（buildYearlyTotals）の責務で、ここは受け取った順に描く
    testWidgets('年別は渡された順序のまま描く', (tester) async {
      await _pump(tester, [
        _year(2024, 500),
        _year(2025, 1500),
        _year(2026, 1000),
      ]);

      expect(_rodValues(tester), [500, 1500, 1000]);
    });
  });

  group('X 軸ラベル', () {
    testWidgets('月別は年を落とした短い形にする', (tester) async {
      await _pump(tester, _twelveMonths(List.filled(12, 1000)));

      // 末尾アンカーで間引くので、いちばん新しい 12 月は必ず残る
      expect(find.text('12月'), findsOneWidget);
      // 長い形を軸に出すと 360px では必ず重なる
      expect(find.text('2026年12月'), findsNothing);
    });

    testWidgets('年別は年をそのまま出す', (tester) async {
      await _pump(tester, [_year(2025, 500), _year(2026, 1000)]);

      expect(find.text('2026年'), findsOneWidget);
      expect(find.text('2025年'), findsOneWidget);
    });

    // fl_chart は軸ラベルが重なっても例外を出さない。読めない図が静かに出来る
    testWidgets('12 本でも軸ラベルが重ならず、読める本数が残る', (tester) async {
      final items = _twelveMonths(List.filled(12, 1000));
      await _pump(tester, items);

      _expectLabelsReadable(tester, items, minVisible: 6);
    });

    // 全期間モードは年数が増え続ける。30 年でも間引きで読める形を保つ
    testWidgets('30 年でも例外を出さず、ラベルが重ならない', (tester) async {
      final items = [
        for (var i = 0; i < 30; i++) _year(1997 + i, (i + 1) * 1000),
      ];
      await _pump(tester, items);

      expect(tester.takeException(), isNull);
      expect(_data(tester).barGroups.length, 30);

      // 全部は載らないので間引かれているが、読めない図にもしない
      expect(_visibleXLabelRects(tester, items).length, lessThan(items.length));
      _expectLabelsReadable(tester, items, minVisible: 4);
    });

    // 末尾アンカーの担保。間引きが効いた瞬間に直近の期間が落ちると、
    // 読み手が最初に見たい値の位置が分からなくなる
    testWidgets('間引かれても末尾のラベルは残る', (tester) async {
      final items = [
        for (var i = 0; i < 30; i++) _year(1997 + i, (i + 1) * 1000),
      ];
      await _pump(tester, items);

      expect(find.text('2026年'), findsOneWidget);
    });
  });

  group('Y 軸', () {
    // 目盛りを 1/2/5 × 10^n に丸めるので、¥13.3万 のような半端な軸にならない
    testWidgets('最大値をきりの良い目盛りまで切り上げる', (tester) async {
      await _pump(tester, [_month(7, 700)]);

      expect(_data(tester).maxY, 800);
      expect(_data(tester).minY, 0);
      expect(find.text('¥0'), findsOneWidget);
      expect(find.text('¥800'), findsOneWidget);
    });

    // formatYen をそのまま軸に使うと ¥999,999,999,999 が 360px の 1/3 以上を
    // 占めてグラフ本体が潰れる。kMaxAmount は DB の CHECK が現に許す値
    testWidgets('上限額でもレイアウトが崩れず、軸ラベルが畳まれない', (tester) async {
      await _pump(tester, [_month(7, kMaxAmount)]);

      expect(tester.takeException(), isNull);
      expect(_data(tester).maxY, 1000000000000);
      expect(find.text('¥1兆'), findsOneWidget);
      expect(_isEllipsized(tester, '¥1兆'), isFalse);
      expect(_isEllipsized(tester, '¥5000億'), isFalse);
    });

    // 上の isFalse の対照。maxLines を外すと didExceedMaxLines は常に false を
    // 返すので、isFalse だけでは「畳まれない」ことを何も守れない
    testWidgets('幅が足りなければ軸ラベルは 1 行のまま省略される', (tester) async {
      await _pump(tester, [_month(7, kMaxAmount)], width: 100);

      expect(tester.takeException(), isNull);
      expect(_isEllipsized(tester, '¥5000億'), isTrue);
    });
  });

  group('ツールチップ', () {
    // Canvas 直描きなので find.text('¥1,500') では拾えない。
    // 軸ラベルは間引かれうるので、ツールチップ側は年月まで出す
    testWidgets('期間と実額を 2 行で出す', (tester) async {
      await _pump(tester, [_month(3, 1500), _month(4, 2000)]);

      final data = _data(tester);
      final group = data.barGroups.first;
      final item = data.barTouchData.touchTooltipData.getTooltipItem(
        group,
        0,
        group.barRods.single,
        0,
      );

      expect(item, isNotNull);
      // 金額は概数ではなく実額。ここで formatYenAxis を使うと嘘の額が出る
      expect(item!.text, '2026年3月\n¥1,500');
    });

    testWidgets('年別では年だけを出す', (tester) async {
      await _pump(tester, [_year(2026, 120000)]);

      final data = _data(tester);
      final group = data.barGroups.single;
      final item = data.barTouchData.touchTooltipData.getTooltipItem(
        group,
        0,
        group.barRods.single,
        0,
      );

      expect(item!.text, '2026年\n¥120,000');
    });

    // 背景に棒と同じ色を敷くので、文字色を固定するとダークテーマで溶ける
    testWidgets('文字色を棒の輝度から選ぶ', (tester) async {
      await _pump(tester, [_month(3, 1500)]);

      final data = _data(tester);
      final group = data.barGroups.single;
      final item = data.barTouchData.touchTooltipData.getTooltipItem(
        group,
        0,
        group.barRods.single,
        0,
      );

      expect(
        item!.textStyle.color,
        labelColorOn(trendColor(_theme.colorScheme)),
      );
    });

    // 文字色は labelColorOn(背景) で決まる。背景だけ別の色に変わると
    // 白背景に白文字のような読めないツールチップになるが、文字色しか
    // 見ていないテストでは気付けない
    testWidgets('背景に棒と同じ色を敷き、タップを受け付ける', (tester) async {
      await _pump(tester, [_month(3, 1500)]);

      final data = _data(tester);
      expect(
        data.barTouchData.touchTooltipData.getTooltipColor(
          data.barGroups.single,
        ),
        trendColor(_theme.colorScheme),
      );
      // enabled を落とすとツールチップは二度と出ない
      expect(data.barTouchData.enabled, isTrue);
    });
  });

  group('棒の色', () {
    // 直書きへの差し戻しを検知する。カテゴリ色の流用も同時に弾く
    testWidgets('chart_palette の trendColor を使う', (tester) async {
      await _pump(tester, [_month(3, 1500), _month(4, 2000)]);

      final expected = trendColor(_theme.colorScheme);
      for (final group in _data(tester).barGroups) {
        expect(group.barRods.single.color, expected);
      }
      // カテゴリ ID から選ぶ色を流用していない
      expect(expected, isNot(categoryColor(0)));
    });
  });

  group('目盛りの下限', () {
    // 金額は正の整数しか入らないので、目盛りが 1 円未満になると存在しない額が
    // 軸に並ぶ。合計 1 円だと 0.25 → 0.5 円刻みになり、formatYen が 0.5 を
    // 四捨五入して `¥0 / ¥1 / ¥1` と同じラベルが 2 つ出ていた（実測）
    testWidgets('合計が 1〜2 円でも目盛りが 1 円刻み以上になる', (tester) async {
      for (final total in [1.0, 2.0, 3.0]) {
        await _pump(tester, [_month(7, total)]);

        expect(
          _data(tester).gridData.horizontalInterval,
          greaterThanOrEqualTo(1),
          reason: '合計 $total 円で目盛りが 1 円未満になった',
        );
        expect(
          find.text('¥1'),
          findsOneWidget,
          reason: '合計 $total 円で同じ金額のラベルが複数出ている',
        );
      }
    });
  });

  group('端末の文字サイズ', () {
    // 幅だけを実測して高さを定数にすると、文字サイズを 1 段階上げただけで
    // X 軸ラベルの下端が黙って切れる。fl_chart は reservedSize で子の高さを
    // tight に縛るので、はみ出した分は ellipsis 指定の Text がクリップし、
    // 例外も overflow の縞模様も出ない（実測: scale 1.15 以降 14.0 で頭打ち）
    testWidgets('文字サイズを上げても X 軸ラベルが縦に切れない', (tester) async {
      final items = _twelveMonths(List.filled(12, 1000));

      await _pump(tester, items);
      final base = tester.getSize(find.text('12月')).height;

      await _pump(tester, items, textScale: 2.0);
      final scaled = tester.getSize(find.text('12月')).height;

      // 切れていれば帯の高さで頭打ちになり、倍率に比例しない
      expect(scaled, closeTo(base * 2, 1.0));
    });

    testWidgets('文字サイズを上げてもラベルが重ならない', (tester) async {
      final items = _twelveMonths(List.filled(12, 1000));

      await _pump(tester, items, textScale: 2.0);

      expect(tester.takeException(), isNull);
      // 文字が大きいぶん本数は減るが、末尾（直近の月）は必ず残る
      _expectLabelsReadable(tester, items, minVisible: 2);
      expect(find.text('12月'), findsOneWidget);
    });
  });

  group('軸と目盛り線', () {
    // FlTitlesData の既定は 4 辺すべて表示。明示的に消さないと上辺に棒の
    // インデックス、右辺に ¥ の付かない生の数値が並ぶ（既存の find.text は
    // ¥ 付きしか見ていないので 1 件も落ちない）
    testWidgets('上辺と右辺には軸を出さない', (tester) async {
      await _pump(tester, [_month(7, 700)]);

      final titles = _data(tester).titlesData;
      expect(titles.topTitles.sideTitles.showTitles, isFalse);
      expect(titles.rightTitles.sideTitles.showTitles, isFalse);
      expect(titles.leftTitles.sideTitles.showTitles, isTrue);
      expect(titles.bottomTitles.sideTitles.showTitles, isTrue);
    });

    // 金額を読めるのは「Y 軸ラベルとグリッド線が同じ間隔で並ぶ」ため。
    // 間隔がずれると、ラベルの位置に線が無い図になる
    testWidgets('水平グリッド線を Y 軸ラベルと同じ間隔で引く', (tester) async {
      await _pump(tester, [_month(7, 700)]);

      final data = _data(tester);
      expect(data.gridData.show, isTrue);
      // 縦線は棒と重なって読みにくくなるので引かない
      expect(data.gridData.drawVerticalLine, isFalse);
      expect(data.gridData.horizontalInterval, 200);
      expect(data.titlesData.leftTitles.sideTitles.interval, 200);
    });
  });

  group('高さ', () {
    // ListView の子なので自分で高さを持つ。既定値が潰れても画面側は既定の
    // まま使うので、潰れたグラフがそのまま出る
    testWidgets('既定は 200、指定すればその高さで描く', (tester) async {
      final items = [_month(7, 700)];

      await _pump(tester, items);
      expect(tester.getSize(find.byType(PeriodBarChart)).height, 200);

      await _pump(tester, items, height: 120);
      expect(tester.getSize(find.byType(PeriodBarChart)).height, 120);
    });
  });
}
