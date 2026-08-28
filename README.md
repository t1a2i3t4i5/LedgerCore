# LedgerCore

サーバ不要・**モバイル端末内だけで完結するオフライン家計簿アプリ**（Flutter）。

バックエンド・REST API・認証は持たない。データは [drift](https://drift.simonbinder.eu/)（SQLite）で端末内に保存し、集計・割り勘の計算も端末側で行う。

## 特徴

- **オフライン完結** — ネットワーク・サーバ・アカウント登録は不要。起動後すぐ利用できる
- **取引管理** — 収支の追加・編集・削除、月切り替え、カテゴリ/登録者/金額/メモでのフィルタ・ソート
  - 金額は **1 円以上 999,999,999,999 円以下の整数**のみ（小数は入力欄で受け付けず、DB の CHECK 制約でも弾く）
  - 以前のバージョンで小数や上限超過の金額を保存していた場合、**初回起動時の移行で四捨五入・削除される**（元の値は復元できない。詳細は [docs/db-schema.md](docs/db-schema.md)）
- **保存先の月の明示** — 表示中の月と違う月の取引を入力しているときは日付欄で警告し、保存後は保存先の月を名指しした通知を出す（`その月を表示` でその月へ移動できる）
- **カテゴリ管理** — 初回起動時に既定カテゴリ（食費・日用品ほか）を自動投入
- **メンバー管理** — 端末内でメンバーを登録し、割り勘の対象にする
- **サマリー** — 月／年／全期間を切り替えて集計を見る
  - 月 — カテゴリ別・メンバー別の集計。カテゴリ別は金額・構成比（%）と大小を走査できる横帯を並べる
  - 年 — 月別の支出推移を棒グラフで表示し、その年のカテゴリ別を並べる
  - 全期間 — 年別の支出推移を棒グラフで表示する
- **割り勘** — メンバー全員で均等割りし、各自の過不足と精算方法を算出（すべて端末内で計算）

## 必要環境

- [Flutter](https://docs.flutter.dev/get-started/install) 3.41 以上（Dart SDK `>=3.7.0 <4.0.0`）
- iOS/macOS で動かす場合は Xcode（初回のみ `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` が必要なことがある）

### 対応プラットフォーム

`android/ ios/ macos/ linux/ windows/ web/` のビルド設定は `flutter create` が生成したものが揃っているが、**動作確認済みと言えるプラットフォームはまだ無い**。

`web` は対象外。`drift_flutter` を web で動かすには `sqlite3.wasm` と `drift_worker.js` を `web/` に置く必要があるが、現状置いていない。

## 開発コマンド

```bash
flutter pub get                 # 依存取得
dart run build_runner build     # drift のコード生成（*.g.dart）
flutter run                     # 実行
flutter test                    # テスト
flutter analyze                 # 静的解析
dart format lib test            # 整形
bash tool/sync_codex_agents.sh  # Codex のスキルリンクとエージェント定義を生成
```

- 既存の生成物と衝突する場合は `dart run build_runner build --delete-conflicting-outputs`
- 初回起動で既定カテゴリと既定メンバー「自分」が投入され、すぐに入力を始められる
- Claude Code で作業する場合、`.claude/settings.json` の `PostToolUse` フックが `.dart` ファイルの編集直後に `dart format` を自動実行する（`jq` が必要）
- 整形スタイルと SDK 下限を変える際の注意点は [docs/design-notes.md](docs/design-notes.md) の「コード整形は language version で決まる」を参照

`AppDatabase.schemaVersion` を上げたときは、固定スキーマと移行ヘルパを再生成して同じコミットに含める（手順は [docs/db-schema.md](docs/db-schema.md) の「スキーマを変更するとき」）。

```bash
dart run drift_dev schema dump lib/db/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

## 技術スタック

| 項目       | 内容                                                    |
| ---------- | ------------------------------------------------------- |
| 状態管理   | `provider`（`ChangeNotifier`）                          |
| 永続化     | `drift` + `drift_flutter`（端末内 `ledgercore.sqlite`） |
| 日付整形   | `intl`                                                  |
| グラフ描画 | `fl_chart`（純 Dart 実装。ネイティブ依存・通信なし。支出推移の棒グラフで使う） |
| 操作ログ   | 自前実装（`lib/logging/`）。端末内のファイルへ JSON Lines で追記する |
| ファイル配置 | `path_provider` + `path`（ログの書き込み先の解決だけに使う） |
| コード生成 | `drift_dev` + `build_runner`                            |
| Lint       | `flutter_lints`（`analysis_options.yaml`）              |

## 同梱フォント

アプリは起動後にネットワークへ接続しないため、次の書体を ttf で同梱する。いずれも
[SIL Open Font License 1.1](https://openfontlicense.org/) で提供されており、ライセンス本文も
`assets/fonts/` に保存してアプリのライセンス画面へ登録している。

| 書体 | 同梱ウェイト | 提供元 |
| --- | --- | --- |
| Zen Maru Gothic | Regular (400) / Bold (700) | [Google Fonts](https://github.com/google/fonts/tree/main/ofl/zenmarugothic) |
| Zen Kaku Gothic New | Bold (700) | [Google Fonts](https://github.com/google/fonts/tree/main/ofl/zenkakugothicnew) |
| Outfit | SemiBold (600) | [Outfitio/Outfit-Fonts](https://github.com/Outfitio/Outfit-Fonts) |

取得コマンド（Outfit は可変フォントではなく、上流の静的 ttf を使う）:

```bash
mkdir -p assets/fonts
GOOGLE_FONTS=https://raw.githubusercontent.com/google/fonts/main/ofl
OUTFIT=https://raw.githubusercontent.com/Outfitio/Outfit-Fonts/main
curl -L -o assets/fonts/ZenMaruGothic-Regular.ttf "$GOOGLE_FONTS/zenmarugothic/ZenMaruGothic-Regular.ttf"
curl -L -o assets/fonts/ZenMaruGothic-Bold.ttf "$GOOGLE_FONTS/zenmarugothic/ZenMaruGothic-Bold.ttf"
curl -L -o assets/fonts/ZenKakuGothicNew-Bold.ttf "$GOOGLE_FONTS/zenkakugothicnew/ZenKakuGothicNew-Bold.ttf"
curl -L -o assets/fonts/Outfit-SemiBold.ttf "$OUTFIT/fonts/ttf/Outfit-SemiBold.ttf"
curl -L -o assets/fonts/OFL-ZenMaruGothic.txt "$GOOGLE_FONTS/zenmarugothic/OFL.txt"
curl -L -o assets/fonts/OFL-ZenKakuGothicNew.txt "$GOOGLE_FONTS/zenkakugothicnew/OFL.txt"
curl -L -o assets/fonts/OFL-Outfit.txt "$OUTFIT/OFL.txt"
```

## 構成

```
assets/
└── fonts/                      # 同梱フォントの ttf と SIL OFL 1.1
drift_schemas/                 # 各スキーマバージョンの固定記録（生成物・git 管理）
test/generated_migrations/     # 固定記録から起こした移行ヘルパ（生成物・git 管理）
lib/
├── main.dart                  # 起動・Provider 登録（認証なしでメイン画面へ直行）
├── theme/                     # 配色・書体・角丸・影のテーマとアプリ固有トークン
│   ├── ledger_theme.dart      # ColorScheme と Material コンポーネントテーマ
│   └── ledger_tokens.dart     # 補助色・形状・金額用 TextStyle
├── db/
│   ├── database.dart          # drift のテーブル定義・DAO・集計クエリ
│   ├── database.g.dart        # 生成コード（build_runner）
│   └── summary_calculator.dart# 月次サマリー・割り勘の計算（純関数）
├── models/                    # 表示用モデル（DB の JOIN 結果や入力値を保持する単純なクラス）
│   ├── transaction.dart       # 取引と金額の上限 kMaxAmount
│   ├── category.dart
│   ├── household_member.dart
│   ├── summary.dart           # 月次サマリー（カテゴリ別・メンバー別）
│   └── split.dart             # 割り勘の結果（各自の過不足・精算方法）
├── logging/                   # 操作ログ
│   ├── operation_logger.dart  # 記録の入口と書き出しキュー
│   ├── log_entry.dart         # ログ 1 行のデータと JSON Lines への整形（純関数）
│   ├── log_sink.dart          # 書き出し先の抽象・何もしない実装・テスト用のメモリ実装
│   └── file_log_sink.dart     # ファイルへの追記とサイズによる世代交代
├── providers/                 # 状態管理（provider / ChangeNotifier）
│   ├── month_scoped_provider.dart # 表示月の共通基底
│   ├── member_provider.dart
│   ├── category_provider.dart
│   ├── transaction_provider.dart
│   └── summary_provider.dart
├── screens/
│   ├── main_screen.dart       # ボトムナビゲーションと 5 タブの束ね
│   ├── transactions_screen.dart   # 取引一覧
│   ├── add_transaction_screen.dart# 取引の追加・編集
│   ├── transaction_filter_sheet.dart # 一覧のソート・フィルター設定
│   ├── summary_screen.dart    # サマリー（月 / 年 / 全期間）
│   ├── split_screen.dart      # 割り勘
│   ├── categories_screen.dart # カテゴリ管理
│   └── members_screen.dart    # メンバー管理
└── widgets/                   # 画面から切り離した再利用部品（ウィジェットとは限らない）
    ├── chart_palette.dart     # グラフの色（カテゴリ ID から決まる色・推移グラフの棒の色）
    ├── category_breakdown_row.dart # カテゴリ別の名前・金額・構成比・横帯を束ねる行
    ├── ledger_card.dart       # 白地・角丸・影付きの共通カード
    ├── month_selector.dart    # 月・年の期間選択 UI
    ├── period_bar_chart.dart  # 月別・年別の支出推移を描く棒グラフ
    ├── period_format.dart     # 年月の表示整形（'2026年7月' / 軸用の '7月'）
    ├── ratio_bar.dart         # 金額が合計に占める割合を長さで表す横帯
    └── amount_format.dart      # 金額・構成比の表示整形（¥ 付き / %）と入力欄の全角正規化・記号除去・桁数制限
```

データの流れは一方向。

```
screens → providers → AppDatabase（drift） → SQLite
```

画面から直接 `AppDatabase` を触らず、必ず Provider を経由する。

テーブル定義・ER 図・表示用モデルとの対応は [docs/db-schema.md](docs/db-schema.md) を参照。

## テスト

普段のローカル開発では変更に関係するテストを優先する。PR を作成・更新すると GitHub Actions が `flutter analyze` と全テストを並列に実行する。

`test/` は検証したい層ごとに分かれている。詳しい書き方と落とし穴は [docs/testing.md](docs/testing.md) を参照。

- **純関数** — 月次集計・割り勘などの計算
- **DB** — DAO・期間・制約
- **マイグレーション** — 過去バージョンからの移行と新規作成
- **Provider** — 状態遷移
- **ウィジェット（`test/widgets/`）** — 画面の表示と配線

## ドキュメント

- [docs/db-schema.md](docs/db-schema.md) — テーブル定義・変更手順・マイグレーション履歴
- [docs/design-notes.md](docs/design-notes.md) — 設計上の約束・理由・過去の事故
- [docs/testing.md](docs/testing.md) — テスト規約と、破っても緑のまま通る落とし穴
- [docs/git-workflow.md](docs/git-workflow.md) — ブランチ・PR・レビュー・マージ、issue の運用とリスク判定表
- [.github/ISSUE_TEMPLATE/issue.md](.github/ISSUE_TEMPLATE/issue.md) — issue 本文の型
- [CLAUDE.md](CLAUDE.md) — AI 向け。破ると静かに壊れる約束の索引
