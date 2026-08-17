# テストの書き方の根拠

[CLAUDE.md](../CLAUDE.md) の「テストの書き方」に並べたルールについて、なぜそう書くか・破ると何を見逃すかを書く。ルールの一覧は CLAUDE.md、根拠はこちらにだけ置く。

ここに挙げた規約の多くは **破っても静かにグリーンのまま通る** 性質を持つ。だから規約として残している。

## 純関数として DB なしでテストする

集計・割り勘のロジックは `summary_calculator.dart` に置き、DB なしでテストする（`test/summary_calculator_test.dart`）。

## DB を伴うテストはインメモリ DB を使う

`AppDatabase.forTesting(NativeDatabase.memory())` を使い、実端末のファイルに触らない（`test/database_test.dart`）。

## マイグレーションテストは固定スキーマから起こす

drift の `SchemaVerifier` を使い、`drift_schemas/` に固定した過去バージョンから起こす（`test/database_migration_test.dart`）。手書き DDL で一部のテーブルだけ旧版に差し替える書き方はしない — 検証対象が「実在しない中間状態」になり、変更していないテーブルの移行漏れを見逃す。

## マイグレーションテストに対象バージョンをリテラルで書かない

起点は `GeneratedHelper.versions`（生成物）を回し、終点はその最新版にする。`migrateAndValidate(db, 3)` と終点を数字で書くと、drift は `AppDatabase.schemaVersion` ではなく引数の値まで移行するため、`schemaVersion` を上げてもテストは古い版までを見たままグリーンになる。

起点を絞るときも同じ。「小数を持ちうる版」「`mail` を持つ版」のように**その版が持っていた性質**で `_oldVersions` から導出し、`[1, 2]` のようなリテラルの一覧を置かない。リテラルだと `schemaVersion` を上げるたびに人手で追従させることになり、追従を忘れると seed の INSERT が「そんな列は無い」で落ちる（または、その版だけ検証から静かに漏れる）。導出が空にならないことを 1 本のテストで押さえておく。

## 新規作成時（`onCreate`）のスキーマも検証する

移行のテストだけでは足りない。移行が作り直すのは一部のテーブルだけで、それ以外は「ヘルパ旧版が作った形」対「ヘルパ新版の形」の比較になり、`lib/db/database.dart` の定義が一度も登場しない。素の `AppDatabase.forTesting(NativeDatabase.memory())` に対して `verifier.migrateAndValidate` を呼ぶ。

`db.validateDatabaseSchema()` は使わない — 参照スキーマを同じ生成コードから採るので同語反復になり、常にグリーンになる。

## ウィジェットテストは `test/widgets/` に置く

### fl_chart は「どこが Canvas 直描きか」で検証手段が変わる

かつてここには「fl_chart が扇形や軸に描く文字は `Canvas` 直描きなので `find.text()` では拾えない」と書いてあった。**軸については fl_chart 1.x で成り立たない。** `side_titles_widget.dart` が `SideTitles.getTitlesWidget` の返り値をそのままウィジェットツリーに載せるため、軸ラベルは通常の `Text` として存在する。削除した円グラフ（0.x 系）の扇形ラベルだけを見て一般化したのが元の記述で、`period_bar_chart_test.dart` を書く段で誤りが分かった。

| 描かれるもの | 実体 | 検証手段 |
| --- | --- | --- |
| 軸ラベル（`getTitlesWidget`） | **ウィジェット** | `find.text()` で拾い、`getRect()` で位置も測れる |
| ツールチップの文字 | `Canvas` 直描き | `BarTouchTooltipData.getTooltipItem` を直接呼ぶ |
| 円グラフの扇形ラベル | `Canvas` 直描き | （現在 `lib/` に円グラフは無い） |
| 棒・扇形そのもの | `Canvas` 直描き | `tester.widget<BarChart>(...).data` を見る |

軸ラベルが**ウィジェットとして拾える**ことは、ただ便利なだけではない。fl_chart はラベルが隣と重なっても例外を出さず、はみ出しても overflow の縞模様を出さずに静かに切れる。`takeException()` では崩れを一切捕まえられないので、**描画されたラベルの矩形を `getRect()` で取り、隣接ペアが重なっていないことを直接見る**（`period_bar_chart_test.dart` の `_visibleXLabelRects`）。棒グラフの X 軸には `SideTitles.interval` が効かず（fl_chart が `barGroups` を全数走査する）、間引きは実装側の自前処理なので、ここが壊れると 12 本のラベルが重なった読めない図が黙って出来る。

### 重なりを見るなら「間引かれ過ぎ」も一緒に見る

重なりの検査は**ラベルが減るほど通りやすい**。下限を置かないと、12 本のうち 2 本しか出ていない図がいちばん安全な実装ということになってしまう。実際、間引き幅を広げる改変（`+4` → `+40`）で表示が 12 本から 4 本に落ちても、重なりだけを見るテストは緑のままだった。`_expectLabelsReadable(..., minVisible: n)` のように読める下限を添える。

### `BarChartData` の設定は「消しても緑」になりやすい

`titlesData` の 4 辺・`gridData`・`barTouchData.enabled`・ツールチップの**背景色**は、どれも描画に効くのに `find.text()` には現れない。とくに次の 2 つは実測で確認した。

- `topTitles` / `rightTitles` の `const AxisTitles()` を消すと上辺・右辺に軸が出るが、既定のラベルは `¥` を含まないので `¥` 付きを探す既存の期待とはぶつからず 1 件も落ちない
- ツールチップの文字色は `labelColorOn(背景)` で決まるので、**背景だけ**を別の色に変えると白背景に白文字になるが、文字色しか見ていないテストは通る

`tester.widget<BarChart>(...).data` に対して、これらの値を直接 `expect` する。

### 端末の文字サイズ（`textScaler`）を通すケースを 1 本置く

既定倍率だけで pump すると、`MediaQuery.textScalerOf` を読む実装を消しても検出できない。実際、X 軸の帯の高さを定数にしていた版は、倍率 1.0 のテストを全部通したまま **scale 1.15 でラベルの下端が切れていた**（幅は足りているので重なりの検査もすり抜ける）。

縦の切れは `didExceedMaxLines` では拾えない（`maxLines: 1` を超えるのは行数であって高さではない）。**倍率を変えて `tester.getSize()` の高さが比例するか**を見る。切れていれば帯の高さで頭打ちになり、比例しない。

## 画面サイズはスマホ幅に設定する

`tester.view.physicalSize` で 360x690 にする。既定の 800x600 は実機より広く overflow を見逃す。

金額を描くテストには `kMaxAmount` を使ったケースを置く。`¥999,999,999,999` は実機幅の 1/3 以上を占めるので、短い金額しか描かないと overflow を見逃す（実際、合計パネルが 9.3px はみ出していた）。

## 文字が省略されたかは `didExceedMaxLines` で見る

横幅が足りないときの失敗は 2 種類あり、**片方は例外を出さない**。`Row` などの `RenderFlex` は overflow を例外にするので `takeException()` で捕まるが、`overflow: TextOverflow.ellipsis` を付けた `Text` は幅が足りなければ黙って `…` に畳む。`ListTile` の `title` はこちらに当たる（`trailing` を先に測って残りを `title` に配分するため、`trailing` を長くすると `title` が静かに潰れる）。

さらに **`find.text()` は畳まれた `Text` にもマッチする**。`Text` が持つ文字列を見ているだけで、実際に描かれた字を見ていないためで、`findsOneWidget` は潰れていても通る。省略が起きたかは描画側に訊く。

```dart
import 'package:flutter/rendering.dart'; // material.dart には入っていない

bool _isEllipsized(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;
```

`_isEllipsized` を `isFalse` で使うテストには、**同じファイルに `isTrue` になるケースも置く**。ヘルパ自身が省略を検知できていなければ `isFalse` は常に通り、何も守らないため（`test/widgets/summary_screen_category_test.dart` は 50 文字のカテゴリ名で裏を取っている）。

### 一覧の行は `find.descendant` で束ねて見る

`find.text('¥7,500')` と `find.text('75.0%')` を別々に `findsOneWidget` で見るだけでは、**行と行で中身が入れ替わっても気付けない**。画面全体では集合として一致してしまうためで、「食費 ¥2,500 / 25.0%」「日用品 ¥7,500 / 75.0%」と全カテゴリがずれた画面が緑のまま通る。

行を `find.ancestor` で特定し、その中に金額と % があることを `find.descendant` で見る（`summary_screen_category_test.dart` の `expectRow`）。並び順そのものは `tester.getCenter(...).dy` の大小で見る。

同じ理由で、`find.byType(ListTile)` の**件数だけ**を数えるテストは中身を守らない。件数は行の中身が入れ替わっても変わらないので、名前と金額の対応が崩れる改変はすべてすり抜ける（実測: 名前だけを逆順の項目から採るよう変えても、件数を見るテストは緑のまま通った。束ねて見る形にしたあとは 5 件落ちる）。

### 幅のテストに既定カテゴリ名を使わない

既定カテゴリは「食費」「日用品」など 2〜3 文字しかなく、**幅が足りない実装でも収まってしまう**。実際、カテゴリ別リストの金額と構成比を 1 行に連結していた版は `title` の取り分が 43.5px しか無かったが、「食費」で書いたテストは緑のまま通った（縦積みに直すと 135.5px）。

カテゴリ名は DB 上 50 文字まで入る。幅を見るテストでは `db.insertCategory('食費（外食）')` のように**ユーザーが実際に付ける長さ**（6 文字程度）を seed する。ここを既定カテゴリに戻すと、テストは緑のまま回帰の検知力だけが消える。

## 表示整形は小数を入れた単体テストで守る

画面テストが使う金額はすべて整数なので、`formatYen()` の書式を `#,###` から `#,##0.##` に変えても出力は 1 文字も変わらず、ウィジェットテストは 1 本も落ちない（実測済み）。しかしそれは DB の整数 CHECK 制約の根拠そのものを崩す変更にあたる。`test/widgets/amount_format_test.dart` に `1234.5` や `合計 ÷ 人数` 相当の割り切れない値を入れて、小数部が出ないことを直接押さえる。期待値は実装から導かずリテラルで書く。

## 月を扱うテストは `clock` を注入して固定年月で書く

テストデータを「今月」に置く書き方はしない。seed 時点の `DateTime.now()` と Provider 構築時点の `DateTime.now()` の間で月が変わると落ちるので、月末 23:59 台の CI で不可解に赤くなる。`TransactionProvider(db, clock: () => DateTime(2026, 7, 15))` のように渡し、アプリ全体を組み立てるときは `LedgerApp(db: db, clock: ...)` を使う。

## `clock` は「呼ぶたびに評価される」ことまで固定する

`Clock` を関数型にしてあるのは、アプリを開いたまま日付が変わっても正しく判定するため。固定値を返す clock だけでテストすると、コンストラクタで 1 回読んでキャッシュする実装を素通しする。値を書き換えられる変数を閉じ込めた clock（`var now = ...; () => now`）で 1 本書く。

## 月送りのテストは、ヘッダの年月だけでなく中身の値も見る

ヘッダだけだと「月表示は動いたが再取得していない」を見逃す。月ごとに違う金額を seed して、送った先の金額が出ることまで確認する（`test/widgets/month_navigation_test.dart`）。

## 画面の配線は Provider のテストでは代替できない

左右の矢印を入れ替えても Provider 側のテストは全部通る。矢印と「今月に戻る」は `tester.tap` で実際に押す。

月選択の UI 自体は `lib/widgets/month_selector.dart` の `MonthSelector` に集約してあるので、**画面を足すときに Row を手で複製しない**。ただし集約したのは見た目だけで、どの Provider を渡してどのコールバックを結ぶかは画面ごとに違う。テストも 2 段に分かれる。

- `test/widgets/month_selector_test.dart` — `MonthSelector` 単体。DB も Provider も組み立てず、渡したコールバックが押した矢印どおりに呼ばれるかを直接見る
- `test/widgets/month_navigation_test.dart` — 画面ごとの配線。月送りで**中身の値まで**読み直されるかを 3 画面ぶん見る（上記「月送りのテストは、ヘッダの年月だけでなく中身の値も見る」）

月選択を持つ画面を足したら、後者に 1 画面ぶん足す。前者は増やさなくてよい。

**年単位の送りは `month_navigation_test.dart` に相乗りさせない。** 集計画面は `MonthSelector` を年モードでも使い回すが（`month: null`）、あちらの共通ケースは `'2026年7月'` と「今月に戻る」を期待しており、年モードでは成り立たない。年送りは `test/widgets/summary_period_test.dart` で単独に見る。集計画面の**月**モードは既定なので、`month_navigation_test.dart` の 3 画面ぶんはそのまま通る。

期間モードを持つ画面のテストでは、**モードを跨いだ状態の保存**も見る。`SummaryProvider` は割り勘タブと 1 インスタンスを共有しているので、年を送ったときに月が動いていないか（＝割り勘タブの表示月を巻き込んでいないか）は年モードのままでは分からない。月モードへ戻して年月を読む形で確かめる。タブを離れるとモードが初期化されないことも `LedgerApp` ごと pump して 1 本置く（`MainScreen` は `IndexedStack` を使わず `State` を捨てるため）。

## 取引の日付に依存するテストは、日付ピッカーで明示的に選ぶ

追加画面の既定日付は `clock` ではなく実時刻なので（[design-notes.md](design-notes.md) の「取引追加画面の既定日付はこの規則の対象外」）、既定のまま保存すると期待値がテストを走らせた月に左右される。カレンダーの升目を辿る書き方も初期表示月が実時刻依存になるので、`Icons.edit_outlined` でテキスト入力モードへ切り替えて `MM/DD/YYYY`（ロケール未指定なので en_US 書式）を打ち込む。`test/widgets/save_feedback_test.dart` の `pickDate` が実装例。
