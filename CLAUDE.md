# CLAUDE.md

このファイルは Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイドです。

## プロジェクト概要

**LedgerCore** はサーバ不要・モバイル端末内だけで完結するオフライン家計簿アプリ（Flutter 単体）。

派生元の `Ledger`（Flutter + Spring Boot + PostgreSQL）からバックエンドと DB 依存を撤廃したもので、**このリポジトリにバックエンド・REST API・認証は存在しない**。データはすべて drift（SQLite）で端末内に保存され、集計・割り勘の計算も端末側で行う。

## 技術スタック

| 項目       | 内容                                                       |
| ---------- | ---------------------------------------------------------- |
| 言語・SDK  | Dart `>=3.0.0 <4.0.0` / Flutter 3.41 以上                   |
| 状態管理   | `provider`（`ChangeNotifier`）                             |
| 永続化     | `drift` + `drift_flutter`（端末内 `ledgercore.sqlite`）    |
| 日付整形   | `intl`                                                     |
| コード生成 | `drift_dev` + `build_runner`                               |
| Lint       | `flutter_lints`（`analysis_options.yaml`）                 |

`http` や `shared_preferences` は依存に含まれていない。ネットワーク通信を伴う実装を追加しないこと。

## ディレクトリ構成

```
lib/
├── main.dart                    # エントリポイント。AppDatabase を生成し MultiProvider で配布、MainScreen へ直行
├── db/
│   ├── database.dart            # drift のテーブル定義・DAO・マイグレーション
│   ├── database.g.dart          # build_runner の生成コード（手で編集しない）
│   └── summary_calculator.dart  # 月次サマリー・割り勘の計算（純関数）
├── models/                      # 表示用モデル（DB の JOIN 結果や入力値を保持する単純なクラス）
├── providers/                   # 状態管理。AppDatabase をコンストラクタ注入で受け取る
│   ├── member_provider.dart
│   ├── category_provider.dart
│   ├── transaction_provider.dart
│   └── summary_provider.dart
└── screens/                     # 画面ウィジェット
    ├── main_screen.dart         # NavigationBar の 4 タブ + AppBar から MembersScreen へ遷移
    ├── summary_screen.dart      # 月次サマリー（カテゴリ別・メンバー別）
    ├── transactions_screen.dart # 取引一覧（月切替・フィルタ・ソート）
    ├── transaction_filter_sheet.dart
    ├── add_transaction_screen.dart
    ├── categories_screen.dart   # カテゴリ管理
    ├── split_screen.dart        # 割り勘
    └── members_screen.dart      # メンバー管理
```

データの流れは一方向:

```
screens → providers → AppDatabase（drift） → SQLite
```

画面から直接 `AppDatabase` を触らず、必ず Provider を経由する。

## 主要コマンド

```bash
flutter pub get
```

```bash
dart run build_runner build
```

```bash
flutter run
```

```bash
flutter test
```

```bash
flutter analyze
```

`build_runner` が既存の生成物と衝突する場合は `dart run build_runner build --delete-conflicting-outputs` を使う。

## drift のコード生成

- `lib/db/database.g.dart` は生成物だが **git 管理対象**。`.gitignore` されていない
- `database.dart` のテーブル定義や `@DriftDatabase` を変更したら、必ず `dart run build_runner build` を実行し、`database.g.dart` も同じコミットに含める
- `database.g.dart` を直接編集しない

## DB スキーマ変更時の注意

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

## テスト

```bash
flutter test
```

- `test/summary_calculator_test.dart` — 月次集計・割り勘計算（純関数）
- `test/database_test.dart` — drift の DAO。`AppDatabase.forTesting(NativeDatabase.memory())` でインメモリ DB を使い、実端末のファイルに触らない

DB を伴うテストを書くときは `AppDatabase.forTesting` を使うこと。

## git 運用

ブランチ命名・PR 運用・マージ方式は [docs/git-workflow.md](docs/git-workflow.md) を参照すること。

## 言語設定

- 常に日本語で会話する
- コメントも日本語で記述する
- エラーメッセージの説明も日本語で行う
- ドキュメントも日本語で生成する
