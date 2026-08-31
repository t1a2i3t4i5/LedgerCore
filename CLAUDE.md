# CLAUDE.md

このファイルは、コードを読んでも分からず、破ると静かに壊れる約束の索引。約束の本文・理由・過去の事故はリンク先を正本とする。

## プロジェクト概要

**LedgerCore** はサーバ不要・モバイル端末内だけで完結する Flutter 単体のオフライン家計簿アプリ。
バックエンド・REST API・認証は存在せず、データ・集計・割り勘はすべて端末内で完結する。
`http` や `shared_preferences` は依存に含まれていない。ネットワーク通信を伴う実装を追加しないこと。
機能・技術スタック・環境は [README.md](README.md) を参照すること。

## アーキテクチャ

データの流れは `screens → providers → AppDatabase（drift）→ SQLite` の一方向。
画面から直接 `AppDatabase` を触らず、Provider は `AppDatabase` をコンストラクタ注入で受け取る。
ディレクトリ構成は [README.md](README.md) の「構成」を参照すること。

## 触る前に読むもの

| 触るもの | 読む文書 |
| --- | --- |
| `lib/db/database.dart`、`drift_schemas/`、`schemaVersion` | [docs/db-schema.md](docs/db-schema.md)（テーブル定義・変更手順・マイグレーション履歴） |
| 画面・Provider・ウィジェット | [docs/design-notes.md](docs/design-notes.md)（設計上の約束・理由・過去の事故） |
| `lib/theme/**` | [docs/design-notes.md](docs/design-notes.md)（テーマ層の役割とライト専用の判断） |
| `test/` | [docs/testing.md](docs/testing.md)（テスト規約と、破っても緑のまま通る落とし穴） |
| ブランチ・PR・レビュー・マージ | [docs/git-workflow.md](docs/git-workflow.md)（リスク判定表を含む） |
| issue | [docs/git-workflow.md](docs/git-workflow.md)（運用基準）、[.github/ISSUE_TEMPLATE/issue.md](.github/ISSUE_TEMPLATE/issue.md)（本文の型） |
| コマンド・環境・ディレクトリ構成 | [README.md](README.md) |

## 破ると静かに壊れる約束

- `lib/db/database.g.dart` は生成物だが git 管理対象。テーブル定義を変えたら `dart run build_runner build` の結果を同じコミットに含め、直接編集しない
- `.codex/agents/*.toml` と `.agents/skills` は生成物。`.claude/agents/*.md` を変えたら `tool/sync_codex_agents.sh` を走らせ、TOML を直接編集しない
- `drift_schemas/*.json` と `test/generated_migrations/*.dart` も生成物だが git 管理対象。過去バージョンの JSON は書き換えない（移行テストが変更に追従して緑のままになるため）
- `schemaVersion` を上げるときは [docs/db-schema.md](docs/db-schema.md) の「スキーマを変更するとき」に従う
- 集計ロジックは純関数に置き、`summary_calculator.dart` から DB に触らない
- Provider は `AppDatabase` をコンストラクタ注入で受け取り、状態更新後に `notifyListeners()` を呼ぶ
- 表示用モデルは読み出しが `*View`、書き込みが `*Input`。支払者は `memberId` / `memberName` とし、`User` 系・`Response` / `Request` 系の名前を持ち込まない
- 月の範囲指定は半開区間 `[月初, 翌月初)` で統一する
- ホームの先月比と件数は月モードだけに出す。前月0円は「先月比 —」、比率は `formatRatio()` で小数1桁にする（詳細は `docs/design-notes.md`）
- ホームの精算カードは月モードだけに置き、共有の `SummaryProvider.split` を表示する。カードからのタブ移動も `MainScreen._selectTab` を通す（詳細は `docs/design-notes.md`）
- 表示月の判断に画面から `DateTime.now()` を読まず、`MonthScopedProvider` の `clock` に集約する。取引追加画面の `_spentAt` だけが意図的な例外
- 金額は正の整数のみ。上限は `models/transaction.dart` の `kMaxAmount` だけを直す（validator と DB の CHECK 制約が参照するスキーマ定義値）
- 金額表示は `widgets/amount_format.dart` の `formatYen()`、入力欄は `AmountInputFormatter`、構成比は `formatRatio()`、年月は `widgets/period_format.dart` の `formatPeriod()` / `formatPeriodShort()` を使い、画面側で書式を組み立て直さない
- グラフの色は `widgets/chart_palette.dart` を使い直書きしない。グラフウィジェットは `AppDatabase` も Provider も参照せず、表示データを引数で受け取る
- 配色・書体・角丸・影は `lib/theme/` の `ColorScheme` / `LedgerTokens` から採り、画面に色リテラルを書かない
- 本文の Zen Maru Gothic は Regular のみ同梱する。明示的な太字は `LedgerTokens.heading` を使う（M3 ラベルの w500 は代替描画を許容。詳細は `docs/design-notes.md`）
- 画面の大見出しは `widgets/page_header.dart` を使い、ルートタブでは本文と一緒にスクロールさせる。ホームは月・年で `MonthSelector`、全期間で `PageHeader` を使う。push 先のカテゴリ・メンバー管理は唯一の戻る導線を残す `PinnedBackPageHeader`。取引追加・編集画面は専用の 3 分割ヘッダを使う
- 取引入力のカテゴリは `FormField<int>` 内の `ChoiceChip` を `Wrap` で並べ、選択時に保存値と `didChange()` を同期する。件数が多い場合も画面全体の縦スクロールで選べるようにする
- 操作ログは `lib/logging/` の `OperationLogger` だけを通す。取引のメモ本文とフィルターの検索語を書かず、例外文字列は `log_entry.dart` の `sanitizeError()` を通す。`info()` / `error()` は `void` で呼び出し側に `await` させない
- ログ共有は `LogShare` を通し、`withPausedWrites` で読み出した退避→現行のコピーだけを渡す。Documents をファイル App に公開しない（詳細は `docs/design-notes.md`）
- 書き込み系（`create` / `update` / `delete`）にログのために足した `try` は必ず `rethrow` する

### コード整形

`pubspec.yaml` の `environment.sdk` 下限を動かしたら `flutter pub get` を走らせる。全 `.dart` が再整形対象になるため、詳細は [docs/design-notes.md](docs/design-notes.md) の「コード整形は language version で決まる」を参照する。

## git 運用

ブランチ・PR・レビュー・マージは [docs/git-workflow.md](docs/git-workflow.md) を参照すること。
レビュー方式は変更リスクの 3 段階で選び、同文書の判定表に従うこと。
issue の運用基準は [docs/git-workflow.md](docs/git-workflow.md) の「issue の運用」、本文の型は [.github/ISSUE_TEMPLATE/issue.md](.github/ISSUE_TEMPLATE/issue.md) を参照すること。

## 言語設定

- 常に日本語で会話する
- コメントも日本語で記述する
- エラーメッセージの説明も日本語で行う
- ドキュメントも日本語で生成する
