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

`AppDatabase.schemaVersion` は現在 `4`。テーブルやカラムを変更する場合は:

1. `schemaVersion` をインクリメントする
2. `MigrationStrategy` に `onUpgrade` を追加して移行処理を書く
3. 固定スキーマと移行ヘルパを再生成する（上記「スキーマ検証用の生成物」）

これを怠ると、既にアプリを起動したことのある端末の DB と食い違って実行時エラーになる。

`MigrationStrategy.onCreate` では既定カテゴリ 10 件（食費・日用品ほか）と既定メンバー「自分」を投入し、`beforeOpen` で `PRAGMA foreign_keys = ON` を有効化している。

## 設計上の約束

根拠と過去の事故は [docs/design-notes.md](docs/design-notes.md) にある。守るべきことだけをここに並べる。

- 集計ロジックは純関数に置く（`summary_calculator.dart` は DB に触らない）
- Provider は `AppDatabase` を注入で受け取る。状態更新後は `notifyListeners()` を呼ぶ
- `lib/models/` の表示用モデルは読み出し用が `*View`、書き込み用が `*Input`。`Response` / `Request` を復活させない。素の `Category` / `Transaction` は drift の生成クラスが使っているので避ける
- 支払者は `Members` テーブルなので、表示層でも `memberId` / `memberName` と呼ぶ。`User` 系の名前を持ち込まない（このアプリにアカウントも認証も存在しない）
- 月の範囲指定は半開区間 `[月初, 翌月初)` で統一する
- 表示月の判断に画面から `DateTime.now()` を読まない。`MonthScopedProvider` の `clock` に集約する
  - 取引追加画面の既定日付（`_spentAt`）だけは例外で、意図的に実時刻を使う
  - 保存先の月が表示月と違うことは、日付欄の `helperText` と保存後の SnackBar で知らせる。表示月は自動で切り替えない
  - アクション付きの SnackBar は `floating` + 下 88px の `margin` で FAB を避ける。タブを移ったら `hideCurrentSnackBar()` を呼ぶ
  - 月をまたぐ操作は Provider 側で `fetch()` まで済ませる。月ジャンプは `goToMonth(year, month)` を使う
- 集計画面の期間モード（月／年／全期間）は `SummaryProvider` が持つ。画面の `State` に持たせない（`MainScreen` が `IndexedStack` を使わないのでタブを離れると破棄される）
  - 年の軸は表示月から独立させる（`SummaryProvider._yearAxis`）。`MonthScopedProvider` の `year` を年送りに使うと、割り勘タブの表示期間ごと 1 年動く（同じインスタンスを共有しているため）
  - `fetch()` は月次サマリーと割り勘を**モードに関わらず常に取る**。モードで出し分けるのは年次データだけ
  - 年モードにメンバー別は出さない（`YearlySummary` に `byMember` が無い。足すならデータ層まで波及するので別 issue）
- 見出しか期間ナビを出したら、その下に必ず何かを描く。空表示は `summary_screen.dart` の `_EmptySection` に寄せ、分岐ごとに書き写さない
- 金額は正の整数のみ。上限は `models/transaction.dart` の `kMaxAmount` だけを直す（入力側の validator と DB の CHECK 制約が両方これを参照する）
  - `kMaxAmount` はスキーマ定義値でもあるので、変えるなら「DB スキーマ変更時の注意」の手順まで必要
- 金額の入力欄には必ず `widgets/amount_format.dart` の `AmountInputFormatter` を付ける
- 金額を画面に出すときは `widgets/amount_format.dart` の `formatYen()` を使う。画面側で `NumberFormat` を作らない（`¥` 込み・小数なし。DB の整数 CHECK 制約がこの書式を根拠にしている）
  - 同じファイルの `formatYenAxis()`（`¥12.5万` の形）は**グラフの軸ラベル専用**。丸めるので実額の表示には使わない。`formatYen()` の「小数部を出さない」契約はこの追加でも緩んでいない
- 構成比（%）を画面に出すときは同じファイルの `formatRatio()` を使い、`toStringAsFixed` を各所で組み立て直さない（金額と同じ行に並ぶので書式が対で決まる。呼び出しが 1 か所になった今も画面に書き戻さない）
  - 丸めて合計 100% にならないのは仕様（33.3% × 3 = 99.9%）。補正処理を入れない
  - 集計画面のカテゴリ別リストでは、金額と % を `ListTile` の `trailing` に**縦に積む**。1 行に連結すると `title` の幅が足りずカテゴリ名が黙って畳まれる
- カテゴリ別の構成比にグラフを足さない。PR #14 で入れて PR #65 の % 併記で情報が完全に重複し、外した経緯がある
  - 取引ゼロの月の「データがありません」は `summary_screen.dart` の `byCategory.isEmpty` 分岐が出す。`summary == null` では受からない（空の `MonthlySummary` が返るため）
  - `fl_chart` は #9 の推移グラフ（`widgets/period_bar_chart.dart`）が使っている。カテゴリ別に戻すためのものではない
- グラフウィジェットは `AppDatabase` も Provider も参照せず、表示データを引数で受け取る
  - `ListView` の子として置くので、グラフは自分で固定高さを持つ（子の高さ制約が非有界）
  - 棒グラフの X 軸ラベルは `SideTitles.interval` が効かない。間引きは `getTitlesWidget` の中で自前でやる
- グラフの色は `widgets/chart_palette.dart` を使い、直書きしない。カテゴリ別は `categoryColor(categoryId)`、推移グラフの棒は `trendColor(colorScheme)`
- 年月を画面に出すときは `widgets/period_format.dart` の `formatPeriod()` / `formatPeriodShort()` を使い、`'$year年$month月'` を各所で組み立て直さない
- 操作ログは `lib/logging/` の `OperationLogger` だけを通す。画面と Provider は `info(op, detail)` / `error(op, e, detail)` しか呼ばない
  - 出力先は端末内のログファイル 1 本（JSON Lines）。**drift のテーブルには入れない**し、履歴画面も作らない
  - `info()` / `error()` は `void`。呼び出し側に `await` させない（書き出しは内部の単一キューで直列化する）。待てるのは `flush()` だけで、production からは呼ばない
  - 書き込み系（`create` / `update` / `delete`）にログのために足した `try` は**必ず `rethrow` する**。例外は今までどおり画面の catch へ届かせる
  - **取引のメモ本文とフィルターの検索語はログに書かない**（`memoLength` と `hasMemoQuery` だけ）。カテゴリ名・メンバー名は書く
    - `detail` から外すだけでは足りない。例外文字列は `log_entry.dart` の `sanitizeError()` を通してから載せる（DB の例外がバインド値ごと `error` に出て、メモ本文が漏れていた）
    - 伏せるのは `, parameters:` からその行の終わりまで。`Causing statement:` の文とその後ろのスタックは残す
  - `runZonedGuarded` のハンドラでは `debugPrint` も呼ぶ。ログに書くだけだと未捕捉の非同期例外がコンソールから消える
  - ログの年月は `2026-08`、時刻はミリ秒 3 桁固定。画面用の `formatPeriod()` を使い回さず、この書式を画面にも出さない
  - `op` は `<対象>.<動作>`、`lv` は `info` / `error` の 2 値だけ。レベルを増やさない

## テストの書き方

根拠と過去に見逃した事故は [docs/testing.md](docs/testing.md) にある。守るべきことだけをここに並べる。

- 集計・割り勘は純関数として DB なしでテストする
- DB を伴うテストは `AppDatabase.forTesting(NativeDatabase.memory())` を使う
- マイグレーションテストは `SchemaVerifier` と `drift_schemas/` の固定スキーマから起こす。手書き DDL で一部のテーブルだけ旧版に差し替えない
- マイグレーションテストに対象バージョンをリテラルで書かない（`GeneratedHelper.versions` を回す）
- 新規作成時（`onCreate`）のスキーマも `verifier.migrateAndValidate` で検証する。`db.validateDatabaseSchema()` は使わない
- ウィジェットテストは `test/widgets/` に置く。fl_chart は**軸ラベルだけがウィジェット**で `find.text()` に載る。ツールチップと扇形ラベルは `Canvas` 直描きなので拾えない
  - グラフは重なってもはみ出しても例外を出さない。軸ラベルの重なりは `getRect()` で隣接ペアを直接見る
  - 重なりを見るなら**間引かれ過ぎの下限も一緒に見る**（ラベルが減るほど重なりの検査は通りやすい）
  - `titlesData` の 4 辺・`gridData`・ツールチップの背景色は消しても緑になる。`BarChart.data` に直接 expect する
- ウィジェットテストの画面サイズは 360x690 にする。金額を描くなら `kMaxAmount` のケースを置く
  - 端末の文字サイズ（`textScaler`）を通すケースも 1 本置く。縦の切れは `didExceedMaxLines` では拾えないので、倍率を変えて `getSize()` の高さが比例するかを見る
- 文字が幅に収まったかは `RenderParagraph.didExceedMaxLines` で見る。`ellipsis` は例外を出さず、`find.text()` は畳まれた `Text` にもマッチするので `findsOneWidget` では守れない
  - 幅を見るテストのカテゴリ名に既定カテゴリ（2〜3 文字）を使わない。幅が足りない実装でも収まってしまう。`insertCategory` でユーザーが付ける長さ（6 文字程度）を seed する
- 一覧の行は `find.ancestor` + `find.descendant` で束ねて見る。画面全体に対する `find.text()` では、行と行で中身が入れ替わっても通ってしまう
- 月を扱うテストは `clock` を注入して固定年月で書く。「今月」にテストデータを置かない
  - `clock` は値を書き換えられる変数を閉じ込めた形（`var now = ...; () => now`）でも 1 本書く
- 月送りのテストは、ヘッダの年月だけでなく中身の値も見る
- 画面の配線は Provider のテストでは代替できない。矢印と「今月に戻る」は `tester.tap` で実際に押す
- 取引の日付に依存するテストは、日付ピッカーをテキスト入力モードにして明示的に選ぶ
- ログのテストは `lib/logging/log_sink.dart` の `MemoryLogSink` を注入する。実ファイルを触らない
  - 行の書式（`toJsonLine`）は純関数として DB もファイルも無しでテストする。**`jsonDecode` して Map で比べない** — キーの順まで固定したいので、出来上がった文字列そのものを期待値に置く
  - `FileLogSink` のテストは `Directory.systemTemp.createTemp()` を渡す（`path_provider` はプラグインなので素の `flutter test` では答えない）
  - **`testWidgets` の中で `logger.flush()` を待たない。** 擬似時間のゾーンに積まれたキューは返ってこず、失敗ではなく 10 分のハングになる。`await tester.pump()` を挟む（`tester.runAsync()` で包むのは逆効果でデッドロックする）
  - 書き込み系の失敗は、金額 0（DB の CHECK 制約）や FK 違反で起こす。閉じた DB への削除は例外にならない
    - カテゴリ・メンバーの追加／改名は 51 文字の名前で落ちる（`withLength(max: 50)` の drift 側検証）。取引の削除だけは制約で落とせないので `customStatement` で `BEFORE DELETE` トリガを張る
    - `fetch()` の失敗は DB を閉じて起こすが、**閉じる前に 1 度読んで開かせる**。一度も開いていない DB は `close()` しても開き直せてしまい失敗しない
  - 失敗ログは `expect(entry['error'], isNotNull)` で終わらせない。理由（`CHECK constraint failed` など）まで見る。例外は `test/matchers.dart` のマッチャで型と文言を縛る
  - 機微な値が漏れないことのテストは実 DB を失敗させて書く。手で組んだ例外文字列だけでは `sqlite3` の書式変更を捕まえられない
  - sink を注入していない対象に `expect(sink.lines, isEmpty)` を書かない。実装が何をしても真になる

## コード整形

`dart format` のスタイルは、実行中の Dart SDK ではなく **language version** で決まる。現在は Dart 3.7 の tall style。

**`dart format` が読むのは `.dart_tool/package_config.json` の `languageVersion` であって `pubspec.yaml` ではない。** `pubspec.yaml` の `environment.sdk` の下限（現在 `>=3.7.0`）はその元になる値で、`flutter pub get` を通して初めて `package_config.json` に反映される。

- **下限を動かしたら必ず `flutter pub get` を走らせる。** 飛ばすと `dart format` は古い `languageVersion` のまま整形する。`dart format` は `dart run` や `flutter test` と違って暗黙の pub get をしないので自己修復しない
  - しばらく触っていないクローンでは `package_config.json` が古いことがある。`.dart` を編集する前に `flutter pub get` を通す。古いまま編集すると、`3.0` の頃の値で 63 ファイル中 30 ファイルが旧スタイルへ書き戻る
- **下限を動かすと全 `.dart` ファイルが再整形の対象になる**。依存更新のついでに触らない。変えるなら整形だけを独立した PR にする
- 下限を下げると旧スタイルに戻る。スタイルが混ざっている箇所を見つけても、そのファイルだけ手で直さない（`dart format` を通す）
- 生成物（`lib/db/database.g.dart` / `test/generated_migrations/*.dart`）も同じ language version で整形されて出る。`build_runner build` と `drift_dev schema generate` のどちらを回しても差分は揺れない
- Claude Code で作業する場合、`.claude/settings.json` の `PostToolUse` フックが `.dart` の編集直後に `dart format` を自動実行する。`jq` に依存している

## git 運用

ブランチ命名・PR 運用・マージ方式は [docs/git-workflow.md](docs/git-workflow.md) を参照すること。

レビュー方式は変更リスクの 3 段階で選ぶ。判定表は [docs/git-workflow.md](docs/git-workflow.md) を参照すること。

issue の書き方は [docs/issue-writing.md](docs/issue-writing.md) を参照すること。

## 言語設定

- 常に日本語で会話する
- コメントも日本語で記述する
- エラーメッセージの説明も日本語で行う
- ドキュメントも日本語で生成する
