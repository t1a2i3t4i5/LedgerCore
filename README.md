# LedgerCore

サーバ不要・**モバイル端末内だけで完結するオフライン家計簿アプリ**（Flutter）。

`Ledger`（Flutter + Spring Boot + PostgreSQL）から派生し、バックエンドと DB 依存を撤廃。
データは [drift](https://drift.simonbinder.eu/)（SQLite）で端末内に保存する。

## 特徴

- **オフライン完結** — ネットワーク・サーバ・アカウント登録は不要。起動後すぐ利用できる
- **取引管理** — 収支の追加・編集・削除、月切り替え、カテゴリ/登録者/金額/メモでのフィルタ・ソート
- **カテゴリ管理** — 初回起動時に既定カテゴリ（食費・日用品ほか）を自動投入
- **メンバー管理** — 端末内でメンバーを登録し、割り勘の対象にする
- **月次サマリー** — カテゴリ別・メンバー別の集計と、カテゴリ別構成比のドーナツグラフ
- **割り勘** — メンバー全員で均等割りし、各自の過不足と精算方法を算出（すべて端末内で計算）

## 必要環境

- [Flutter](https://docs.flutter.dev/get-started/install) 3.41 以上
- iOS/macOS で動かす場合は Xcode（初回のみ `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` が必要なことがある）

## セットアップ

```bash
flutter pub get
# drift のコード生成（*.g.dart）
dart run build_runner build
```

## 実行

```bash
flutter run
```

初回起動で既定カテゴリと既定メンバー「自分」が投入され、すぐに入力を始められる。

## テスト

```bash
flutter test
```

- `test/summary_calculator_test.dart` — 月次集計・割り勘計算（純関数）
- `test/database_test.dart` — drift DAO（インメモリDBで月レンジ・集計・CRUD・外部キー制約を検証）
- `test/database_migration_test.dart` — マイグレーション（`drift_schemas/` に固定した過去バージョンから起こし、移行後のスキーマと新規作成時のスキーマを検証）
- `test/transaction_provider_test.dart` — 取引 Provider の状態遷移（削除が一覧・合計・フィルター結果に波及するか）
- `test/widgets/chart_palette_test.dart` — グラフの色パレット（決定性・WCAG コントラスト）
- `test/widgets/category_pie_chart_test.dart` — カテゴリ別ドーナツグラフ（ウィジェットテスト）
- `test/widgets/summary_screen_chart_test.dart` — サマリー画面へのグラフ組み込み（インメモリDB + Provider）
- `test/widgets/add_transaction_amount_test.dart` — 取引追加・編集画面の金額バリデーション
- `test/widgets/transactions_screen_test.dart` — 取引一覧の削除フロー（長押し → 確認ダイアログ）
- `test/widgets/summary_reflects_delete_test.dart` — 削除がタブをまたいでサマリーに反映されること

## 構成

テーブル定義・ER 図・表示用モデルとの対応は [docs/db-schema.md](docs/db-schema.md) を参照。

```
drift_schemas/                 # 各スキーマバージョンの固定記録（生成物・git 管理）
test/generated_migrations/     # 固定記録から起こした移行ヘルパ（生成物・git 管理）
lib/
├── main.dart                  # 起動・Provider 登録（認証なしでメイン画面へ直行）
├── db/
│   ├── database.dart          # drift のテーブル定義・DAO・集計クエリ
│   ├── database.g.dart        # 生成コード（build_runner）
│   └── summary_calculator.dart# 月次サマリー・割り勘の計算（純関数）
├── models/                    # 表示用モデル
├── providers/                 # 状態管理（provider / ChangeNotifier）
│   ├── member_provider.dart
│   ├── category_provider.dart
│   ├── transaction_provider.dart
│   └── summary_provider.dart
├── screens/                   # 各画面（サマリー / 取引 / カテゴリ / 割り勘 / メンバー管理）
└── widgets/                   # 画面から切り離した再利用ウィジェット
    ├── chart_palette.dart     # グラフの色パレット（カテゴリ ID から決定的に決まる）
    └── category_pie_chart.dart# カテゴリ別構成比のドーナツグラフ
```

- 状態管理: `provider`（ChangeNotifier）
- 永続化: `drift` + `sqlite3`（端末内 `ledgercore.sqlite`）
- グラフ描画: `fl_chart`（純 Dart 実装。ネイティブ依存・ネットワーク通信なし）
