# 設計上の約束の根拠

[CLAUDE.md](../CLAUDE.md) の「設計上の約束」に並べたルールについて、なぜそうしているか・破ると何が起きるかを書く。ルールの一覧は CLAUDE.md、根拠はこちらにだけ置く。

## 集計ロジックは純関数に置く

`summary_calculator.dart` の `buildMonthlySummary` / `buildSplit` は DB に触らず、取引リストを受け取って結果を返す。DB アクセスと計算を混ぜないことでテストしやすさを保つ。

## Provider は `AppDatabase` を注入で受け取る

内部で生成しない。状態更新後は `notifyListeners()` を呼ぶ。

## 月の範囲指定は半開区間

`[月初, 翌月初)` で統一する（`getTransactionsByMonth` 参照）。

## 表示月の判断に画面から `DateTime.now()` を読まない

表示月の状態は `providers/month_scoped_provider.dart` の `MonthScopedProvider` に集約する。初期表示月・`isCurrentMonth`・`changeMonth`・`goToCurrentMonth` はすべて、Provider に注入された `clock`（既定 `DateTime.now`）1 つから導かれる。画面側で now を読み直すと判断材料が 2 層に分かれ、画面テストが実時刻に依存して月末に落ちる。

### 取引追加画面の既定日付はこの規則の対象外

`add_transaction_screen.dart` の `_spentAt` は意図的に実時刻を使う。表示中の月ではなく「今日」を既定にするのは、過去月を見返している最中に思い出した今日の出費を、徴候なく過去月へ沈めないため。表示月に寄せると「月しか選べない UI から日を捏造する」ことにもなる（`spentAt` の日は一覧のアバターとソートに効く）。**このずれは残す前提で、フィードバック側で誤認を潰す**（次項）。

### 保存先の月が表示月と違うことは、画面が言葉で知らせる

既定日付が表示月と独立している以上、両者がずれたまま保存する経路は残る。ずれたまま保存すると一覧にも合計にも何も現れず、成功したのに「保存に失敗した」ようにしか見えない。これを次の 2 段で潰す。

- 保存前: 日付欄の `helperText` に「表示中の 2026年7月 とは別の月です」を出す（事前に気づける）
- 保存後: 成功時は必ず SnackBar を出す。同じ月なら「保存しました」、別の月なら保存先を名指しした「2026年8月に保存しました」＋ `その月を表示` で移動できるようにする

**保存後に表示月を自動で切り替えない。** 結果は必ず見えるようになるが、ユーザーの閲覧文脈を無断で移すことになる。移るかどうかは `その月を表示` を押すかで本人が決める。

### アクション付きの SnackBar は `floating` にして FAB を避ける

SnackBar が出るのは `MainScreen` の Scaffold（ルートの `ScaffoldMessenger`）だが、FAB を持っているのは `TransactionsScreen` の入れ子の Scaffold なので、既定の `fixed` では FAB が押し上げられない。実測で `その月を表示` は FAB にぴたりと重なっており、続けてもう 1 件追加しようとしたタップがそのまま月移動になっていた。`behavior: SnackBarBehavior.floating` と下 88px の `margin` で FAB の上へ逃がす。

### タブを移ったら `hideCurrentSnackBar()` を呼ぶ

`main_screen.dart` の `onDestinationSelected` で呼ぶ。SnackBar はルートに出るのでタブを移っても残る。サマリータブで `その月を表示` を押せてしまうと、画面は何も変わらないまま取引一覧の表示月だけが裏で動く。

### 月をまたぐ操作は Provider 側で `fetch()` まで済ませる

`changeMonth` / `goToCurrentMonth` / `goToMonth` は表示月を変えたうえで再取得する。画面に `setYearMonth` と再取得を並べると、取引・サマリー・割り勘の 3 画面で同じ 2 行を書くことになり、片方だけ書き忘れると「月を送ったのに中身が前の月のまま」になる。`setYearMonth` は `@visibleForTesting` で閉じてあるので production からは使わない。

相対移動でない月ジャンプ（保存後の `その月を表示` など）は `goToMonth(year, month)` を使う。`changeMonth` に差分を計算して渡す書き方はしない — 呼ぶ側が年またぎの計算を持つことになる。

### 画面テストは `clock` を注入して固定年月で書く

詳細は [testing.md](testing.md) の「月を扱うテストは `clock` を注入して固定年月で書く」。

## 金額は正の整数のみ

入力側（`add_transaction_screen.dart` の validator）と DB の CHECK 制約の二重で守る。上限は `models/transaction.dart` の `kMaxAmount` を両方が参照し、入力欄の桁数制限も同じ値から導出しているので、変えるときはそこだけを直す。片方にしか無い条件を足すと「画面では通るのに保存で落ちる」か、その逆になる。ただし割り勘の `fairShare` は `合計 ÷ 人数` の導出値なので小数のまま。

**`kMaxAmount` はスキーマ定義値でもある。** CHECK 制約にリテラルとして焼き込まれるため、値を変えるだけでは済まない。`schemaVersion` のインクリメントと移行、固定スキーマの再生成まで必要（CLAUDE.md の「DB スキーマ変更時の注意」）。

金額を描くウィジェットテストには `kMaxAmount` を使ったケースを置く（[testing.md](testing.md) 参照）。

## 金額の入力欄は `AmountInputFormatter` を使う

`widgets/amount_input_formatter.dart` にあり、取引の追加・編集画面とフィルターシートが共有する。全角の正規化・記号の除去・桁数制限をここに閉じ込めてあるので、金額を入力する欄を新しく足すときも必ずこれを付ける。付け忘れると同じアプリ内で「追加画面では全角が通るのに、こちらでは理由の分からないエラーになる」という食い違いが出る。

## グラフウィジェットは `AppDatabase` も Provider も参照しない

表示データはすべて引数で受け取る。DB なしでウィジェットテストできる状態を保つ。

## グラフの色は `chart_palette.dart` に集約する

`categoryColor(categoryId)` はカテゴリ ID から決定的に色を選ぶので、同じカテゴリはグラフ・凡例・リストで常に同じ色になる。新しいグラフを追加するときもここを使い、ウィジェット内で色を直書きしない。
