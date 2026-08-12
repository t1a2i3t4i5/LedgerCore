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

起点は `GeneratedHelper.versions`（生成物）を回し、終点はその最新版にする。`migrateAndValidate(db, 3)` と書くと、drift は `AppDatabase.schemaVersion` ではなく引数の値まで移行するため、`schemaVersion` を 4 に上げてもテストは v1 → v3 だけを見たままグリーンになる。

## 新規作成時（`onCreate`）のスキーマも検証する

移行のテストだけでは足りない。移行が作り直すのは一部のテーブルだけで、それ以外は「ヘルパ旧版が作った形」対「ヘルパ新版の形」の比較になり、`lib/db/database.dart` の定義が一度も登場しない。素の `AppDatabase.forTesting(NativeDatabase.memory())` に対して `verifier.migrateAndValidate` を呼ぶ。

`db.validateDatabaseSchema()` は使わない — 参照スキーマを同じ生成コードから採るので同語反復になり、常にグリーンになる。

## ウィジェットテストは `test/widgets/` に置く

fl_chart が扇形や軸に描く文字は `Canvas` 直描きなので `find.text()` では拾えない。検証は凡例など通常のウィジェットに対して行う。

## 画面サイズはスマホ幅に設定する

`tester.view.physicalSize` で 360x690 にする。既定の 800x600 は実機より広く overflow を見逃す。

金額を描くテストには `kMaxAmount` を使ったケースを置く。`¥999,999,999,999` は実機幅の 1/3 以上を占めるので、短い金額しか描かないと overflow を見逃す（実際、合計パネルが 9.3px はみ出していた）。

## 月を扱うテストは `clock` を注入して固定年月で書く

テストデータを「今月」に置く書き方はしない。seed 時点の `DateTime.now()` と Provider 構築時点の `DateTime.now()` の間で月が変わると落ちるので、月末 23:59 台の CI で不可解に赤くなる。`TransactionProvider(db, clock: () => DateTime(2026, 7, 15))` のように渡し、アプリ全体を組み立てるときは `LedgerApp(db: db, clock: ...)` を使う。

## `clock` は「呼ぶたびに評価される」ことまで固定する

`Clock` を関数型にしてあるのは、アプリを開いたまま日付が変わっても正しく判定するため。固定値を返す clock だけでテストすると、コンストラクタで 1 回読んでキャッシュする実装を素通しする。値を書き換えられる変数を閉じ込めた clock（`var now = ...; () => now`）で 1 本書く。

## 月送りのテストは、ヘッダの年月だけでなく中身の値も見る

ヘッダだけだと「月表示は動いたが再取得していない」を見逃す。月ごとに違う金額を seed して、送った先の金額が出ることまで確認する（`test/widgets/month_navigation_test.dart`）。

## 画面の配線は Provider のテストでは代替できない

取引・サマリー・割り勘の 3 画面は同じ月選択 Row を手で複製している。実際、左右の矢印を入れ替えても Provider 側のテストは全部通る。矢印と「今月に戻る」は `tester.tap` で実際に押す。

## 取引の日付に依存するテストは、日付ピッカーで明示的に選ぶ

追加画面の既定日付は `clock` ではなく実時刻なので（[design-notes.md](design-notes.md) の「取引追加画面の既定日付はこの規則の対象外」）、既定のまま保存すると期待値がテストを走らせた月に左右される。カレンダーの升目を辿る書き方も初期表示月が実時刻依存になるので、`Icons.edit_outlined` でテキスト入力モードへ切り替えて `MM/DD/YYYY`（ロケール未指定なので en_US 書式）を打ち込む。`test/widgets/save_feedback_test.dart` の `pickDate` が実装例。
