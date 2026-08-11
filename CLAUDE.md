# CLAUDE.md

このファイルは Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイドです。

セットアップ手順・機能一覧・ディレクトリ構成の詳細は [README.md](README.md) を参照すること。このファイルには、コードを読んだだけでは分かりにくい運用ルールと設計上の約束を書く。

## プロジェクト概要

**LedgerCore** はサーバ不要・モバイル端末内だけで完結するオフライン家計簿アプリ（Flutter 単体）。

**このリポジトリにバックエンド・REST API・認証は存在しない**。データはすべて drift（SQLite）で端末内に保存され、集計・割り勘の計算も端末側で行う。

## 技術スタック

使っているライブラリの一覧は [README.md](README.md) の「技術スタック」を参照すること。

`http` や `shared_preferences` は依存に含まれていない。ネットワーク通信を伴う実装を追加しないこと。

## アーキテクチャ

ディレクトリ構成は [README.md](README.md) の「構成」を参照すること。データの流れは一方向:

```
screens → providers → AppDatabase（drift） → SQLite
```

画面から直接 `AppDatabase` を触らず、必ず Provider を経由する。`providers/` は `AppDatabase` をコンストラクタ注入で受け取る。

## drift のコード生成

コマンドそのものは [README.md](README.md) の「開発コマンド」にある。ここには守るべき条件だけを書く。

- `lib/db/database.g.dart` は生成物だが **git 管理対象**。`.gitignore` されていない
- `database.dart` のテーブル定義や `@DriftDatabase` を変更したら、必ず `dart run build_runner build` を実行し、`database.g.dart` も同じコミットに含める
- `database.g.dart` を直接編集しない

### スキーマ検証用の生成物

マイグレーションテストは `drift_schemas/*.json`（各バージョンの正しい形の記録）と `test/generated_migrations/*.dart`（そこから起こした移行ヘルパ）を使う。**どちらも生成物だが git 管理対象**。`schemaVersion` を上げたら README の再生成コマンド（`drift_dev schema dump` / `generate`）を実行し、同じコミットに含める。

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

根拠と過去の事故は [docs/design-notes.md](docs/design-notes.md) にある。守るべきことだけをここに並べる。

- 集計ロジックは純関数に置く（`summary_calculator.dart` は DB に触らない）
- Provider は `AppDatabase` を注入で受け取る。状態更新後は `notifyListeners()` を呼ぶ
- `TransactionResponse` / `userId` / `userName` が指しているのは `Members` テーブル。認証やネットワークの層を想定しない
- 月の範囲指定は半開区間 `[月初, 翌月初)` で統一する
- 表示月の判断に画面から `DateTime.now()` を読まない。`MonthScopedProvider` の `clock` に集約する
  - 取引追加画面の既定日付（`_spentAt`）だけは例外で、意図的に実時刻を使う
  - 保存先の月が表示月と違うことは、日付欄の `helperText` と保存後の SnackBar で知らせる。表示月は自動で切り替えない
  - アクション付きの SnackBar は `floating` + 下 88px の `margin` で FAB を避ける。タブを移ったら `hideCurrentSnackBar()` を呼ぶ
  - 月をまたぐ操作は Provider 側で `fetch()` まで済ませる。月ジャンプは `goToMonth(year, month)` を使う
- 金額は正の整数のみ。上限は `models/transaction.dart` の `kMaxAmount` だけを直す（入力側の validator と DB の CHECK 制約が両方これを参照する）
  - `kMaxAmount` はスキーマ定義値でもあるので、変えるなら「DB スキーマ変更時の注意」の手順まで必要
- 金額の入力欄には必ず `widgets/amount_input_formatter.dart` の `AmountInputFormatter` を付ける
- グラフウィジェットは `AppDatabase` も Provider も参照せず、表示データを引数で受け取る
- グラフの色は `widgets/chart_palette.dart` の `categoryColor(categoryId)` を使い、直書きしない

## テストの書き方

根拠・過去に見逃した事故・書くときの具体的な手順は [docs/testing.md](docs/testing.md) にある。守るべきことだけをここに並べる。

- 集計・割り勘は純関数として DB なしでテストする
- DB を伴うテストは `AppDatabase.forTesting(NativeDatabase.memory())` を使う
- マイグレーションテストは `SchemaVerifier` と `drift_schemas/` の固定スキーマから起こす。手書き DDL で一部のテーブルだけ旧版に差し替えない
- マイグレーションテストに対象バージョンをリテラルで書かない（`GeneratedHelper.versions` を回す）
- 新規作成時（`onCreate`）のスキーマも `verifier.migrateAndValidate` で検証する。`db.validateDatabaseSchema()` は使わない
- ウィジェットテストは `test/widgets/` に置く。fl_chart が描く文字は `find.text()` では拾えない
- ウィジェットテストの画面サイズは 360x690 にする。金額を描くなら `kMaxAmount` のケースを置く
- 月を扱うテストは `clock` を注入して固定年月で書く。「今月」にテストデータを置かない
  - `clock` は値を書き換えられる変数を閉じ込めた形（`var now = ...; () => now`）でも 1 本書く
- 月送りのテストは、ヘッダの年月だけでなく中身の値も見る
- 画面の配線は Provider のテストでは代替できない。矢印と「今月に戻る」は `tester.tap` で実際に押す
- 取引の日付に依存するテストは、日付ピッカーをテキスト入力モードにして明示的に選ぶ

## git 運用

ブランチ命名・PR 運用・マージ方式は [docs/git-workflow.md](docs/git-workflow.md) を参照すること。

## 言語設定

- 常に日本語で会話する
- コメントも日本語で記述する
- エラーメッセージの説明も日本語で行う
- ドキュメントも日本語で生成する
