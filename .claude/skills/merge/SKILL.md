---
name: merge
description: レビュー済みの PR を squash マージし、ブランチと worktree を片付ける。ユーザーが `/merge` を明示実行したときだけ使い、自然文からは起動しない。
argument-hint: "[PR番号]"
arguments: pr
disable-model-invocation: true
allowed-tools:
  - Bash(cd *)
  - Bash(git worktree list:*)
  - Bash(git rev-parse:*)
  - Bash(git status:*)
  - Bash(git branch:*)
  - Bash(git fetch:*)
  - Bash(git pull --ff-only origin main)
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

## 0. `/merge` の実行を承認として扱う

ユーザーが `/merge` を実行したことをマージまでの承認として扱います。本文を再掲して確認し直しません。レビュー済みかどうかも聞き返しません。`disable-model-invocation: true` を維持し、自然文からこのスキルを起動しません。

worktree の削除は別です。ユーザーが「ワークツリーも消していいよ」と明示したときだけ手順 6 を実行します。

## 1. 対象 PR を決める

`$pr` の先頭の `#` を落として判定します。

- **数値** → その PR
- **空** → 現在のブランチの PR

対象を決めたら、数値指定・省略のどちらでも `gh pr view <番号> --json number,title,state,isDraft,mergeable,mergeStateStatus,headRefName,headRefOid,headRepositoryOwner,isCrossRepository,baseRefName` で同じ項目を取得します。

PR が見つからない、または `state` が `OPEN` でないときは、そのまま伝えて終了します。作り直しません。

## 2. マージできる状態か外部変更前に確かめる

`gh pr view` の結果と `gh pr checks <番号>` を、次の順序で判定します。`mergeStateStatus` は CI が完了してから見ます。

1. `baseRefName` が `main` 以外 — このスキルは main 向け PR だけを扱うと伝えて終了
2. `isDraft` が `true` — draft 解除後にやり直すよう伝えて終了
3. `mergeable` が `CONFLICTING` — main との衝突をユーザーに伝えて終了
4. `gh pr checks` に失敗がある — どれが落ちたかを伝えて終了
5. `gh pr checks` に `pending` がある — 完了を待つかユーザーに聞く
   - 待たない — 終了
   - 待つ — `gh pr checks <番号> --watch` の完了後に `gh pr view` とチェック結果を取り直し、この手順を再判定
6. pending も失敗もないのに `mergeStateStatus` が `CLEAN` 以外 — GitHub が示した状態を伝えて終了
7. ローカルの `main` をマージ後に fast-forward できる状態へ揃える
   - `git worktree list` で `main` の worktree がある — 現在の worktree ルートを `git rev-parse --show-toplevel` で控え、`cd <main の worktree>` を別の Bash 呼び出しで行う。`git status --porcelain` が空でなければ元の worktree に戻り、未コミット変更があると伝えて終了する。クリーンなら `git pull --ff-only origin main` を実行し、失敗したら元の worktree に戻って終了する。成功後も `git rev-parse HEAD` と直前の pull が取得した `git rev-parse FETCH_HEAD` が一致しなければ、未 push コミットがあると伝え、元の worktree に戻って終了する。一致した場合も元の worktree に戻る
   - `main` の worktree がない — `git fetch origin main:main` を実行し、fast-forward できなければ終了する

すべての条件を通るまで、手順 3 以降の外部状態を変更しません。

**落ちた CI をこのスキルの中で直しません。** 直すのは実装側の仕事です。

## 3. 積み上げ PR があれば先に付け替える

`isCrossRepository` が `false` のときだけ、このブランチを base にしている open PR を探します。fork の head ブランチは本家リポジトリの base になれず、同名の本家ブランチを検索すると無関係な PR を付け替えうるためです。

```bash
gh pr list --state open --base <この PR の headRefName> --json number,title
```

該当があれば、番号を控え、**ブランチを消す前に**1 件ずつ付け替えます。付け替えに成功した番号も記録します。

```bash
gh pr edit <子PR番号> --base main
```

途中で 1 件でも失敗したら、成功済みの子 PR をすべて元の親ブランチへ戻して終了します。

```bash
gh pr edit <成功済みの子PR番号> --base <この PR の headRefName>
```

戻せなかった子 PR があれば、その番号と現在の base を報告します。子 PR の付け替えがすべて完了するまで親 PR をマージしません。

順番を逆にすると子 PR は base が付け替わらず**クローズされ、`gh pr reopen` も `gh pr edit --base` も通らなくなります**。GitHub が自動で付け替えるのは `gh pr merge --delete-branch` と Web UI の Delete branch だけで、REST API の ref 削除はその経路を通りません。

squash 後の main と子ブランチの変更箇所が重なるとコンフリクトすることがあります。親 PR のマージ後に子 PR の状態を取り直し、実際にコンフリクトしている場合だけ rebase が別途要ると手順 7 で報告します。

## 4. マージする — 実行場所で経路が変わる

手順 2 で控えた現在の worktree ルートと、`main` の worktree の有無を使います。

**現在地が `.claude/worktrees/` 配下ではなく、どこも `main` を使っておらず、同一リポジトリの PR の場合**

```bash
gh pr merge <番号> --squash --delete-branch --match-head-commit <headRefOid>
```

**現在地が `.claude/worktrees/` 配下ではなく、どこも `main` を使っておらず、fork からの PR の場合**

```bash
gh pr merge <番号> --squash --match-head-commit <headRefOid>
```

fork 側のブランチはこのスキルから削除しません。

**現在地が `.claude/worktrees/` 配下、または別の worktree が `main` を使っている場合**

`gh pr merge --delete-branch` は現在の worktree を `main` へ切り替えるか、別 worktree の `main` と衝突して落ちます。後続手順の現在地を変えないよう、REST API でリモートだけマージします。`<owner>/<repo>` は `gh repo view --json nameWithOwner` で取ります。

```bash
gh api -X PUT repos/<owner>/<repo>/pulls/<番号>/merge -f merge_method=squash -f sha=<headRefOid>
```

手順 1 で確認した head から更新されていればマージを失敗させます。新しい head の CI と状態を確認し直さず、そのままマージしません。

マージコマンドや API が失敗した、または結果が不明な場合は、最初に `gh pr view <番号> --json state,mergedAt` で実際の状態を取り直します。

- `state` が `MERGED` — 子 PR の base は `main` のままにし、未完了のブランチ削除と `main` 最新化を続ける
- `state` が `MERGED` 以外 — 手順 3 で付け替えた子 PR をすべて `gh pr edit <子PR番号> --base <headRefName>` で元に戻し、親 PR をマージできなかった理由と rollback の結果を報告して終了

マージされていないのに子 PR を `main` 向きのまま残しません。rollback に失敗した子 PR があれば、その番号と現在の base を明記します。

同一リポジトリの PR のときだけ、マージ成功後に本家の head ref を削除します。

```bash
gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<headRefName>
```

`isCrossRepository` が `true` のときは DELETE を実行しません。本家の同名 ref を誤って消さないため、fork 側のブランチは残し、手順 7 でその旨を報告します。

## 5. `main` を最新化する

マージ後に `git worktree list` を取り直します。手順 4 の直接マージ経路では現在の worktree が `main` へ切り替わることがあるため、マージ前の判定を使い回しません。

- `main` を checkout している worktree がある → 現在地を控え、次を**別々の Bash 呼び出し**で行う
  1. `cd <git worktree list で得た main の worktree の実パス>`
  2. `git pull --ff-only origin main`
  3. `cd <元のディレクトリ>`
- どこも checkout していない → `git fetch origin main:main`

`cd` と `git pull` を 1 つの複合コマンドにしません。`cd` の移動先は `git worktree list` が示したパスを引用符で囲んでそのまま使い、変数展開やコマンド置換を入れません。`allowed-tools` はコマンドの後ろだけを可変にした `Bash(cd *)` と、サブコマンドまで固定した `Bash(git pull --ff-only origin main)` を事前承認します。`git -C` の可変パスに任意のオプションを差し込める権限は作りません。

## 6. worktree を片付ける — 明示されたときだけ

手順 0 でユーザーが worktree の削除まで頼んでいて、かつ現在地が `.claude/worktrees/` 配下のときだけ実行します。親リポジトリで動いているなら worktree は触りません。

`git status --porcelain` と `git rev-parse HEAD` を先に見ます。未コミットの差分や未追跡ファイルがある、またはローカル HEAD が手順 1 で控えた `headRefOid` と異なる場合は、**消す前に**破棄対象を列挙してユーザーに確認します。追加の破棄を承認されなければ worktree を残します。

クリーンかつ HEAD が `headRefOid` と一致する場合は、PR に含まれたコミットだけが残っているため、`ExitWorktree` を `action: "remove", discard_changes: true` で呼びます。未コミット変更や PR 外のローカルコミットについて追加承認を得た場合も同じ引数で削除します。

## 7. 報告する

付け替えた子 PR があれば、親 PR のマージ後に `gh pr view <子PR番号> --json number,title,mergeable,mergeStateStatus` で状態を取り直します。

- マージした PR の番号とタイトル
- 削除したブランチ、または fork 由来などで削除しなかった理由
- 更新後の `main` の tip
- 付け替えた子 PR があれば、その番号と再取得した状態。実際にコンフリクトしている場合だけ「rebase が別途要る」旨
- 片付けた worktree、または残した理由

## 規約はここに写さない

リスク判定表とレビュー方式は [`docs/git-workflow.md`](../../../docs/git-workflow.md)、ブランチ命名は同 Step 2 が正本です。ここに書くのはマージと後始末の手順だけです。
