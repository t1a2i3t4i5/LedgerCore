---
name: merge
description: レビュー済みの PR を squash マージし、ブランチと worktree を片付ける。ユーザーが「マージしていいよ」「マージしてください。ワークツリーも消していいよ」と言ったときに使う。
argument-hint: "[PR番号]"
arguments: pr
disable-model-invocation: true
allowed-tools:
  - Bash(git worktree list:*)
  - Bash(git rev-parse:*)
  - Bash(git status:*)
  - Bash(git branch:*)
  - Bash(git fetch:*)
  - Bash(git -C * pull --ff-only origin main)
  - Bash(git log:*)
  - Bash(gh pr view:*)
  - Bash(gh pr list:*)
  - Bash(gh pr checks:*)
  - Bash(gh pr edit:*)
  - Bash(gh pr merge:*)
  - Bash(gh repo view:*)
  - Bash(gh api:*)
  - ExitWorktree
---

PR を squash マージし、ブランチを消して `main` を最新化します。**マージ後の後始末までで終わります** — 実装もレビューも修正もしません。

PR: `$pr`

## 0. ユーザーの依頼を承認として扱う

「マージしていいよ」「マージしてください」はマージまでの承認です。本文を再掲して確認し直しません。レビュー済みかどうかも聞き返しません。

worktree の削除は別です。ユーザーが「ワークツリーも消していいよ」と明示したときだけ手順 6 を実行します。

## 1. 対象 PR を決める

`$pr` の先頭の `#` を落として判定します。

- **数値** → その PR
- **空** → 現在のブランチの PR。`gh pr view --json number,title,state,isDraft,mergeable,mergeStateStatus,headRefName,baseRefName`

PR が見つからない、または `state` が `OPEN` でないときは、そのまま伝えて終了します。作り直しません。

## 2. マージできる状態か 1 回で確かめる

`gh pr view` の結果と `gh pr checks <番号>` を見ます。

| 見るもの | 止める条件 |
| --- | --- |
| `isDraft` | `true` — draft 解除後にやり直すよう伝えて終了 |
| `mergeable` | `CONFLICTING` — main との衝突をユーザーに伝えて終了 |
| `mergeStateStatus` | `CLEAN` 以外 — GitHub が示した状態を伝えて終了 |
| `gh pr checks` | 失敗しているチェックがある — どれが落ちたかを伝えて終了 |
| `gh pr checks` | まだ `pending` — 完了を待つかどうかユーザーに聞く |

すべての条件を通るまで、手順 3 以降の外部状態を変更しません。

**落ちた CI をこのスキルの中で直しません。** 直すのは実装側の仕事です。

## 3. 積み上げ PR があれば先に付け替える

このブランチを base にしている open PR を探します。

```bash
gh pr list --state open --base <この PR の headRefName> --json number,title
```

該当があれば、**ブランチを消す前に**先に付け替えます。

```bash
gh pr edit <子PR番号> --base main
```

順番を逆にすると子 PR は base が付け替わらず**クローズされ、`gh pr reopen` も `gh pr edit --base` も通らなくなります**。GitHub が自動で付け替えるのは `gh pr merge --delete-branch` と Web UI の Delete branch だけで、REST API の ref 削除はその経路を通りません。

squash 運用なので、付け替えた子 PR は main と必ずコンフリクトします（子ブランチには親の個別コミットが残り、main には squash された 1 コミットしかない）。子ブランチの rebase が別途要ることを手順 7 の報告に書きます。

## 4. マージする — 実行場所で経路が変わる

`git worktree list` で `main` を checkout しているディレクトリがあるかを見ます。

**どこも `main` を使っていない場合**

```bash
gh pr merge <番号> --squash --delete-branch
```

**別の worktree が `main` を使っている場合**

`gh pr merge` はローカルの `main` を checkout できず `'main' is already used by worktree at ...` で落ちます。REST API でリモートだけマージします。`<owner>/<repo>` は `gh repo view --json nameWithOwner` で取ります。

```bash
gh api -X PUT repos/<owner>/<repo>/pulls/<番号>/merge -f merge_method=squash
gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<headRefName>
```

## 5. `main` を最新化する

- `main` を checkout している worktree がある → `git -C <そのディレクトリ> pull --ff-only origin main`
- どこも checkout していない → `git fetch origin main:main`

## 6. worktree を片付ける — 明示されたときだけ

手順 0 でユーザーが worktree の削除まで頼んでいて、かつ現在地が `.claude/worktrees/` 配下のときだけ実行します。親リポジトリで動いているなら worktree は触りません。

`git status --porcelain` を先に見ます。未コミットの差分や未追跡ファイルが残っていれば、**消す前に**何が消えるかを列挙してユーザーに確認します。クリーンなら `ExitWorktree` を `action: "remove"` で呼びます。

## 7. 報告する

- マージした PR の番号とタイトル
- 削除したブランチ、または削除できなかった理由
- 更新後の `main` の tip
- 付け替えた子 PR があれば、その番号と「rebase が別途要る」旨
- 片付けた worktree、または残した理由

## 規約はここに写さない

リスク判定表とレビュー方式は [`docs/git-workflow.md`](../../../docs/git-workflow.md)、ブランチ命名は同 Step 2 が正本です。ここに書くのはマージと後始末の手順だけです。
