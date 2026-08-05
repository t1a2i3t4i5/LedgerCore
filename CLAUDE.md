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
└── widgets/       # 画面から切り離した再利用ウィジェット（グラフなど）
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

## DB スキーマ変更時の注意

テーブル定義・ER 図・表示用モデルとの対応は [docs/db-schema.md](docs/db-schema.md) にまとめてある。スキーマを変更したらこのドキュメントも同じコミットで更新すること。

`AppDatabase.schemaVersion` は現在 `1`。テーブルやカラムを変更する場合は:

1. `schemaVersion` をインクリメントする
2. `MigrationStrategy` に `onUpgrade` を追加して移行処理を書く

これを怠ると、既にアプリを起動したことのある端末の DB と食い違って実行時エラーになる。

`MigrationStrategy.onCreate` では既定カテゴリ 10 件（食費・日用品ほか）と既定メンバー「自分」を投入し、`beforeOpen` で `PRAGMA foreign_keys = ON` を有効化している。

## 設計上の約束

- **集計ロジックは純関数に置く** — `summary_calculator.dart` の `buildMonthlySummary` / `buildSplit` は DB に触らず、取引リストを受け取って結果を返す。DB アクセスと計算を混ぜないことでテストしやすさを保つ
- **Provider は `AppDatabase` を注入で受け取る** — 内部で生成しない。状態更新後は `notifyListeners()` を呼ぶ
- **命名の名残に注意** — `TransactionResponse` / `userId` / `userName` は派生元の REST API の名前がそのまま残っているもので、実際に指しているのは `Members` テーブル（端末内のメンバー）。API のレスポンスではない
- 月の範囲指定は半開区間 `[月初, 翌月初)` で統一する（`getTransactionsByMonth` 参照）
- **グラフウィジェットは `AppDatabase` も Provider も参照しない** — 表示データはすべて引数で受け取る。DB なしでウィジェットテストできる状態を保つ
- **グラフの色は `widgets/chart_palette.dart` に集約する** — `categoryColor(categoryId)` はカテゴリ ID から決定的に色を選ぶので、同じカテゴリはグラフ・凡例・リストで常に同じ色になる。新しいグラフを追加するときもここを使い、ウィジェット内で色を直書きしない

## テストの書き方

- 集計・割り勘のロジックは純関数として `summary_calculator.dart` に置き、DB なしでテストする（`test/summary_calculator_test.dart`）
- DB を伴うテストは `AppDatabase.forTesting(NativeDatabase.memory())` でインメモリ DB を使い、実端末のファイルに触らない（`test/database_test.dart`）
- ウィジェットテストは `test/widgets/` に置く。fl_chart が扇形や軸に描く文字は `Canvas` 直描きなので `find.text()` では拾えない。検証は凡例など通常のウィジェットに対して行う
- ウィジェットテストの画面サイズは `tester.view.physicalSize` でスマホ幅（360x690）に設定する。既定の 800x600 は実機より広く overflow を見逃す

## git 運用

ブランチ命名・PR 運用・マージ方式は [docs/git-workflow.md](docs/git-workflow.md) を参照すること。

## 言語設定

- 常に日本語で会話する
- コメントも日本語で記述する
- エラーメッセージの説明も日本語で行う
- ドキュメントも日本語で生成する
