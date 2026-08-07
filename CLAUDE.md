# CLAUDE.md

このファイルは Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイドです。

セットアップ手順・機能一覧・ディレクトリ構成の詳細は [README.md](README.md) を参照すること。このファイルには、コードを読んだだけでは分かりにくい運用ルールと設計上の約束を書く。

## プロジェクト概要

**LedgerCore** はサーバ不要・モバイル端末内だけで完結するオフライン家計簿アプリ（Flutter 単体）。

派生元の `Ledger`（Flutter + Spring Boot + PostgreSQL）からバックエンドと DB 依存を撤廃したもので、**このリポジトリにバックエンド・REST API・認証は存在しない**。データはすべて drift（SQLite）で端末内に保存され、集計・割り勘の計算も端末側で行う。

## 技術スタック

| 項目       | 内容                                                    |
| ---------- | ------------------------------------------------------- |
| 言語・SDK  | Dart `>=3.0.0 <4.0.0`（必要な Flutter バージョンは README.md） |
| 状態管理   | `provider`（`ChangeNotifier`）                          |
| 永続化     | `drift` + `drift_flutter`（端末内 `ledgercore.sqlite`） |
| 日付整形   | `intl`                                                  |
| グラフ描画 | `fl_chart`（純 Dart 実装。ネイティブ依存・通信なし）    |
| コード生成 | `drift_dev` + `build_runner`                            |
| Lint       | `flutter_lints`（`analysis_options.yaml`）              |

`http` や `shared_preferences` は依存に含まれていない。ネットワーク通信を伴う実装を追加しないこと。

## アーキテクチャ

```
lib/
├── main.dart      # AppDatabase を生成し MultiProvider で配布、MainScreen へ直行（認証なし）
├── db/            # drift のテーブル定義・DAO（database.dart）と集計の純関数（summary_calculator.dart）
├── models/        # 表示用モデル（DB の JOIN 結果や入力値を保持する単純なクラス）
├── providers/     # 状態管理。AppDatabase をコンストラクタ注入で受け取る
├── screens/       # 画面ウィジェット
└── widgets/       # 画面から切り離した再利用部品（グラフ・色パレット・入力フォーマッタ。ウィジェットとは限らない）
```

データの流れは一方向:

```
screens → providers → AppDatabase（drift） → SQLite
```

画面から直接 `AppDatabase` を触らず、必ず Provider を経由する。

## 主要コマンド

```bash
flutter pub get                 # 依存取得
dart run build_runner build     # drift のコード生成（*.g.dart）
flutter run                     # 実行
flutter test                    # テスト
flutter analyze                 # 静的解析
```

`build_runner` が既存の生成物と衝突する場合は `dart run build_runner build --delete-conflicting-outputs` を使う。

## drift のコード生成

- `lib/db/database.g.dart` は生成物だが **git 管理対象**。`.gitignore` されていない
- `database.dart` のテーブル定義や `@DriftDatabase` を変更したら、必ず `dart run build_runner build` を実行し、`database.g.dart` も同じコミットに含める
- `database.g.dart` を直接編集しない

### スキーマ検証用の生成物

マイグレーションテストは `drift_schemas/*.json`（各バージョンの正しい形の記録）と `test/generated_migrations/*.dart`（そこから起こした移行ヘルパ）を使う。**どちらも生成物だが git 管理対象**。`schemaVersion` を上げたら次を実行して同じコミットに含める。

```bash
dart run drift_dev schema dump lib/db/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

`dump` は現在のコードから新しいバージョンの JSON を 1 つ足すだけ。**過去バージョンの JSON は書き換えない** — 書き換えると「そのバージョンの DB がどんな形だったか」の記録が失われ、移行テストが自分の変更に追従してグリーンのままになる。

## DB スキーマ変更時の注意

テーブル定義・ER 図・表示用モデルとの対応は [docs/db-schema.md](docs/db-schema.md) にまとめてある。スキーマを変更したらこのドキュメントも同じコミットで更新すること。

`AppDatabase.schemaVersion` は現在 `3`。テーブルやカラムを変更する場合は:

1. `schemaVersion` をインクリメントする
2. `MigrationStrategy` に `onUpgrade` を追加して移行処理を書く
3. 固定スキーマと移行ヘルパを再生成する（上記「スキーマ検証用の生成物」）

これを怠ると、既にアプリを起動したことのある端末の DB と食い違って実行時エラーになる。

`MigrationStrategy.onCreate` では既定カテゴリ 10 件（食費・日用品ほか）と既定メンバー「自分」を投入し、`beforeOpen` で `PRAGMA foreign_keys = ON` を有効化している。

## 設計上の約束

- **集計ロジックは純関数に置く** — `summary_calculator.dart` の `buildMonthlySummary` / `buildSplit` は DB に触らず、取引リストを受け取って結果を返す。DB アクセスと計算を混ぜないことでテストしやすさを保つ
- **Provider は `AppDatabase` を注入で受け取る** — 内部で生成しない。状態更新後は `notifyListeners()` を呼ぶ
- **命名の名残に注意** — `TransactionResponse` / `userId` / `userName` は派生元の REST API の名前がそのまま残っているもので、実際に指しているのは `Members` テーブル（端末内のメンバー）。API のレスポンスではない
- 月の範囲指定は半開区間 `[月初, 翌月初)` で統一する（`getTransactionsByMonth` 参照）
- **表示月の状態は `providers/month_scoped_provider.dart` の `MonthScopedProvider` に集約する** — 画面ウィジェットから `DateTime.now()` を読まない。初期表示月・`isCurrentMonth`・`changeMonth`・`goToCurrentMonth` はすべて、Provider に注入された `clock`（既定 `DateTime.now`）1 つから導かれる。画面側で now を読み直すと判断材料が 2 層に分かれ、画面テストが実時刻に依存して月末に落ちる
  - **月をまたぐ操作は Provider 側で `fetch()` まで済ませる** — `changeMonth` / `goToCurrentMonth` は表示月を変えたうえで再取得する。画面に `setYearMonth` と再取得を並べると、取引・サマリー・割り勘の 3 画面で同じ 2 行を書くことになり、片方だけ書き忘れると「月を送ったのに中身が前の月のまま」になる
  - **画面テストは `clock` を注入して固定年月で書く** — テストデータを「今月」に置く書き方は、seed 時点の now と Provider 構築時点の now がずれると落ちる。`LedgerApp` にも `clock` を通してあるのでアプリ全体を組み立てるテストでも固定できる
- **金額は正の整数のみ** — 入力側（`add_transaction_screen.dart` の validator）と DB の CHECK 制約の二重で守る。上限は `models/transaction.dart` の `kMaxAmount` を両方が参照し、入力欄の桁数制限も同じ値から導出しているので、変えるときはそこだけを直す。片方にしか無い条件を足すと「画面では通るのに保存で落ちる」か、その逆になる。ただし割り勘の `fairShare` は `合計 ÷ 人数` の導出値なので小数のまま
  - **`kMaxAmount` はスキーマ定義値でもある** — CHECK 制約にリテラルとして焼き込まれるため、値を変えるだけでは済まない。`schemaVersion` のインクリメントと移行、固定スキーマの再生成まで必要（下記「DB スキーマ変更時の注意」）
  - **金額を描くウィジェットテストには `kMaxAmount` を使ったケースを置く** — `¥999,999,999,999` は実機幅の 1/3 以上を占める。短い金額しか描かないと overflow を見逃す（実際、合計パネルが 9.3px はみ出していた）
- **金額の入力欄は `widgets/amount_input_formatter.dart` の `AmountInputFormatter` を使う** — 取引の追加・編集画面とフィルターシートが共有する。全角の正規化・記号の除去・桁数制限をここに閉じ込めてあるので、金額を入力する欄を新しく足すときも必ずこれを付ける。付け忘れると同じアプリ内で「追加画面では全角が通るのに、こちらでは理由の分からないエラーになる」という食い違いが出る
- **グラフウィジェットは `AppDatabase` も Provider も参照しない** — 表示データはすべて引数で受け取る。DB なしでウィジェットテストできる状態を保つ
- **グラフの色は `widgets/chart_palette.dart` に集約する** — `categoryColor(categoryId)` はカテゴリ ID から決定的に色を選ぶので、同じカテゴリはグラフ・凡例・リストで常に同じ色になる。新しいグラフを追加するときもここを使い、ウィジェット内で色を直書きしない

## テストの書き方

- 集計・割り勘のロジックは純関数として `summary_calculator.dart` に置き、DB なしでテストする（`test/summary_calculator_test.dart`）
- DB を伴うテストは `AppDatabase.forTesting(NativeDatabase.memory())` でインメモリ DB を使い、実端末のファイルに触らない（`test/database_test.dart`）
- マイグレーションテストは drift の `SchemaVerifier` を使い、`drift_schemas/` に固定した過去バージョンから起こす（`test/database_migration_test.dart`）。手書き DDL で一部のテーブルだけ旧版に差し替える書き方はしない — 検証対象が「実在しない中間状態」になり、変更していないテーブルの移行漏れを見逃す
- **マイグレーションテストに対象バージョンをリテラルで書かない** — 起点は `GeneratedHelper.versions`（生成物）を回し、終点はその最新版にする。`migrateAndValidate(db, 3)` と書くと、drift は `AppDatabase.schemaVersion` ではなく引数の値まで移行するため、`schemaVersion` を 4 に上げてもテストは v1 → v3 だけを見たままグリーンになる
- **新規作成時（`onCreate`）のスキーマが固定スキーマと一致することも検証する** — 移行のテストだけでは足りない。移行が作り直すのは一部のテーブルだけで、それ以外は「ヘルパ旧版が作った形」対「ヘルパ新版の形」の比較になり、`lib/db/database.dart` の定義が一度も登場しない。素の `AppDatabase.forTesting(NativeDatabase.memory())` に対して `verifier.migrateAndValidate` を呼ぶ。`db.validateDatabaseSchema()` は使わない — 参照スキーマを同じ生成コードから採るので同語反復になり、常にグリーンになる
- ウィジェットテストは `test/widgets/` に置く。fl_chart が扇形や軸に描く文字は `Canvas` 直描きなので `find.text()` では拾えない。検証は凡例など通常のウィジェットに対して行う
- ウィジェットテストの画面サイズは `tester.view.physicalSize` でスマホ幅（360x690）に設定する。既定の 800x600 は実機より広く overflow を見逃す

## git 運用

ブランチ命名・PR 運用・マージ方式は [docs/git-workflow.md](docs/git-workflow.md) を参照すること。

## 言語設定

- 常に日本語で会話する
- コメントも日本語で記述する
- エラーメッセージの説明も日本語で行う
- ドキュメントも日本語で生成する
