# LedgerCore

サーバ不要・**モバイル端末内だけで完結するオフライン家計簿アプリ**（Flutter）。

`Ledger`（Flutter + Spring Boot + PostgreSQL）から派生し、バックエンドと DB 依存を撤廃。
データは [drift](https://drift.simonbinder.eu/)（SQLite）で端末内に保存する。

## 特徴

- **オフライン完結** — ネットワーク・サーバ・アカウント登録は不要。起動後すぐ利用できる
- **取引管理** — 収支の追加・編集・削除、月切り替え、カテゴリ/登録者/金額/メモでのフィルタ・ソート
- **カテゴリ管理** — 初回起動時に既定カテゴリ（食費・日用品ほか）を自動投入
- **メンバー管理** — 端末内でメンバーを登録し、割り勘の対象にする
- **月次サマリー** — カテゴリ別・メンバー別の集計
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
- `test/database_test.dart` — drift DAO（インメモリDBで月レンジ・集計・CRUD を検証）

## 構成

```
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
└── screens/                   # 各画面（サマリー / 取引 / カテゴリ / 割り勘 / メンバー管理）
```

- 状態管理: `provider`（ChangeNotifier）
- 永続化: `drift` + `sqlite3`（端末内 `ledgercore.sqlite`）
