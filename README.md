# LedgerCore

サーバ不要・**モバイル端末内だけで完結するオフライン家計簿アプリ**（Flutter）。

`Ledger`（Flutter + Spring Boot + PostgreSQL）から派生し、バックエンドと DB 依存を撤廃。
データは [drift](https://drift.simonbinder.eu/)（SQLite）で端末内に保存する。

## 特徴

- **オフライン完結** — ネットワーク・サーバ・アカウント登録は不要。起動後すぐ利用できる
- **取引管理** — 収支の追加・編集・削除、月切り替え、カテゴリ/登録者/金額/メモでのフィルタ・ソート
  - 金額は **1 円以上 999,999,999,999 円以下の整数**のみ（小数は入力欄で受け付けず、DB の CHECK 制約でも弾く）
  - 以前のバージョンで小数や上限超過の金額を保存していた場合、**初回起動時の移行で四捨五入・削除される**（元の値は復元できない。詳細は [docs/db-schema.md](docs/db-schema.md)）
- **保存先の月の明示** — 表示中の月と違う月の取引を入力しているときは日付欄で警告し、保存後は保存先の月を名指しした通知を出す（`その月を表示` でその月へ移動できる）
- **カテゴリ管理** — 初回起動時に既定カテゴリ（食費・日用品ほか）を自動投入
- **メンバー管理** — 端末内でメンバーを登録し、割り勘の対象にする
- **月次サマリー** — カテゴリ別・メンバー別の集計と、カテゴリ別構成比のドーナツグラフ
- **割り勘** — メンバー全員で均等割りし、各自の過不足と精算方法を算出（すべて端末内で計算）

## 必要環境

- [Flutter](https://docs.flutter.dev/get-started/install) 3.41 以上（Dart SDK `>=3.0.0 <4.0.0`）
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
```

- 既存の生成物と衝突する場合は `dart run build_runner build --delete-conflicting-outputs`
- 初回起動で既定カテゴリと既定メンバー「自分」が投入され、すぐに入力を始められる

`AppDatabase.schemaVersion` を上げたときは、固定スキーマと移行ヘルパを再生成して同じコミットに含める（理由と注意点は [CLAUDE.md](CLAUDE.md)）。

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
| グラフ描画 | `fl_chart`（純 Dart 実装。ネイティブ依存・通信なし）    |
| コード生成 | `drift_dev` + `build_runner`                            |
| Lint       | `flutter_lints`（`analysis_options.yaml`）              |

## 構成

```
drift_schemas/                 # 各スキーマバージョンの固定記録（生成物・git 管理）
test/generated_migrations/     # 固定記録から起こした移行ヘルパ（生成物・git 管理）
lib/
├── main.dart                  # 起動・Provider 登録（認証なしでメイン画面へ直行）
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
├── providers/                 # 状態管理（provider / ChangeNotifier）
│   ├── month_scoped_provider.dart # 表示月の共通基底（clock 注入・月送り・今月判定）
│   ├── member_provider.dart
│   ├── category_provider.dart
│   ├── transaction_provider.dart
│   └── summary_provider.dart
├── screens/
│   ├── main_screen.dart       # ボトムナビゲーションと 5 タブの束ね
│   ├── transactions_screen.dart   # 取引一覧
│   ├── add_transaction_screen.dart# 取引の追加・編集
│   ├── transaction_filter_sheet.dart # 一覧のソート・フィルター設定
│   ├── summary_screen.dart    # 月次サマリー
│   ├── split_screen.dart      # 割り勘
│   ├── categories_screen.dart # カテゴリ管理
│   └── members_screen.dart    # メンバー管理
└── widgets/                   # 画面から切り離した再利用部品（ウィジェットとは限らない）
    ├── chart_palette.dart     # グラフの色パレット（カテゴリ ID から決定的に決まる）
    ├── category_pie_chart.dart# カテゴリ別構成比のドーナツグラフ
    └── amount_input_formatter.dart # 金額入力欄の全角正規化・記号除去・桁数制限
```

データの流れは一方向。

```
screens → providers → AppDatabase（drift） → SQLite
```

画面から直接 `AppDatabase` を触らず、必ず Provider を経由する。

テーブル定義・ER 図・表示用モデルとの対応は [docs/db-schema.md](docs/db-schema.md) を参照。

## テスト

```bash
flutter test
flutter analyze
```

`test/` の構成は検証したい層ごとに分かれている。

- **純関数** — 月次集計・割り勘は DB に触らない純関数として `lib/db/summary_calculator.dart` に置き、DB なしで検証する
- **DB** — インメモリ DB（`AppDatabase.forTesting`）で DAO・月レンジ・外部キー制約・CHECK 制約を検証する。実端末のファイルには触らない
- **マイグレーション** — `drift_schemas/` に固定した過去バージョンから起こし、移行後と新規作成時の両方のスキーマを検証する
- **Provider** — 状態遷移（削除の波及、表示月の繰り上げ／繰り下げ）を検証する。表示月は `clock` を注入して固定年月で書く
- **ウィジェット（`test/widgets/`）** — 画面の配線を実際にタップして検証する。矢印を入れ替えても Provider のテストは全部通るため、画面側は Provider のテストで代替できない。画面サイズは実機に合わせて 360x690 にする

## ドキュメント

- [docs/db-schema.md](docs/db-schema.md) — テーブル定義・ER 図・表示用モデルとの対応
- [docs/git-workflow.md](docs/git-workflow.md) — ブランチ命名・PR 運用・マージ方式
- [CLAUDE.md](CLAUDE.md) — 設計上の約束とテストの書き方（コードを読んだだけでは分かりにくい運用ルール）
