---
name: quick-review
description: 別コンテキストのレビュアー 1 名で作業差分または PR をレビューする。通常リスクの変更に使う。
argument-hint: "[PR番号]"
arguments: pr
allowed-tools:
  - Read
  - Bash(git rev-parse:*)
  - Bash(git merge-base:*)
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(git status:*)
  - Bash(git branch:*)
  - Bash(gh pr diff:*)
  - Agent
---

別コンテキストのレビュアー 1 名で通常リスクの差分をレビューし、報告だけで終わります。修正、実測、PR へのコメント投稿はしません。

## 1. 対象を決める

引数 `$pr` の先頭の `#` を落として判定します。

- **空** → **作業差分モード**。`main...HEAD`（main 側の進行を混ぜない 3 点表記）と未コミット変更の両方。未コミット変更は `git diff HEAD` と、`git status --porcelain` の `??` 行にある未追跡ファイルからなる。`git diff` は未追跡ファイルを出さないため、必ず両方を見る
- **数値** → **PR モード**。`gh pr diff <番号>`

どちらのモードかを最初に宣言します。作業差分モードで `main...HEAD` が空かつ作業ツリーもクリーンなら、対象がないと伝え、レビュアーを起動せず終了します。

## 2. リスク段階を確認する

`docs/git-workflow.md` のリスク判定表を読みます。高リスクならレビューを始めず、PR モードでは「高リスクなので `/independent-review <番号>` を使ってください」、作業差分モードでは `/independent-review` を使うよう報告して終了します。判定条件はここに写しません。

## 3. レビュー中に読まないもの

あなたもレビュアーも、終了まで `gh pr view` / `gh pr comment` / `gh pr checks` / `gh issue`（全サブコマンド） / `gh api` / `gh browse` を実行しません。既存の判断に引きずられて、まだ指摘されていない欠陥を落とさないためです。

## 4. `reviewer-quick` を 1 体だけ起動する

渡すプロンプトは対象と差分取得コマンドだけにし、観点は指示しません。

```
LedgerCore の以下の差分を、定義済みの出力フォーマットでレビューしてください。
対象: <作業差分モード: ブランチ xxx の main からの差分と未コミット変更 / PR モード: PR #N>
差分取得コマンド（これ以外の差分取得手段は使わないこと）:
  <作業差分> git diff main...HEAD および git diff HEAD
               加えて、次の未追跡ファイルを Read で全文読む: <?? のパス。なければ「なし」>
  <PR>       gh pr diff <N>
```

## 5. 重大度を付ける

`.claude/skills/independent-review/SKILL.md` の重大度表だけを読み、適用します。表はここに写しません。

## 6. 実測せず報告する

実測は行いません。[致命] または [重大] が 1 件でもあれば、末尾で PR モードなら `/independent-review <番号>`、作業差分モードなら `/independent-review` への引き上げを促します。

重大度順の通し番号 1 本で、ブロッカー（[致命] [重大]）は「対象・何が壊れるか・直し方」を付け、それ以外は 1 行ずつ報告します。ブロッカーがなければ「なし」と書きます。修正も PR へのコメント投稿もしません。

## 規約はここに写さない

`docs/git-workflow.md` / `docs/design-notes.md` / `docs/testing.md` の本文と、`.claude/skills/independent-review/SKILL.md` の重大度表は書き写しません。ここに書くのは通常リスクのレビュー手順だけです。
