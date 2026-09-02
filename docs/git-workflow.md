# git 運用ガイド

このリポジトリ固有のブランチ・PR・レビュー・マージ運用をまとめる。各スキルの実行手順は `.claude/skills/<name>/SKILL.md` を正本とする。

## 運用方針

- **GitHub Flow** を採用し、`main` へ直接 push しない
- 機能・修正ごとにブランチと PR を作る
- 変更リスクに応じた方式でレビューする
- **squash merge + ブランチ自動削除**を使い、`main` は PR 1 つ = 1 コミットにして revert しやすくする
- PR 操作には [`gh`](https://cli.github.com/) を使う

## issue の運用

issue は実装を始めるための必須書類ではない。**後で扱う仕事と、実装前に残す価値がある仕様判断の記録**として使う。

### issue を作らない場合

- 今すぐ着手する、やることが明確な小変更
- 1 つの PR で完結する UI 調整・不具合修正・リファクタリング・docs 修正
- 実装しながら安全に決められる内部構造の変更

この場合は直接実装し、PR 本文に目的・変更内容・確認方法を書く。

### issue を作る場合

- 今すぐ着手せず、バックログに残す
- 利用者から見える仕様について判断を残す
- 複数 PR に分かれる
- DB スキーマ変更や既存データの変換がある
- 金額計算、データ消失、プライバシーに関わる
- PR で見つかった別件を、現在の差分へ混ぜず後回しにする

DB 移行などの高リスク変更では、移行後のデータ、失敗時の扱い、回帰テストを完了条件へ追加する。

迷ったら、今すぐ実装する明確な作業は issue なし、後で思い出す必要がある作業は issue ありとする。

### 作成時の確認

ユーザーが「issue にして」「issue を作って」「起票して」と明示した依頼は、issue 作成までを承認済みとして扱う。重要な仕様判断が残っていなければ、本文を再掲してもう一度承認を求めない。

「issue の形に整理したい」「案を見たい」という依頼では作成せず、本文案を提示する。

明らかな重複がないかは作成前に確認する。ただし、過去の全 issue・PR を網羅的に調査することは通常の必須工程にしない。

本文の型は [Issue Template](../.github/ISSUE_TEMPLATE/issue.md)、AI からの起票手順は [`write-issue`](../.claude/skills/write-issue/SKILL.md) を正本とする。

## 通常の開発フロー

### Step 1. `main` を最新化

```bash
git switch main
git pull
```

### Step 2. 機能ブランチを切る

```bash
git switch -c feat/budget-alert
```

#### ブランチ命名規則

| プレフィックス | 用途 | 例 |
| --- | --- | --- |
| `feat/` | 新機能 | `feat/budget-alert` |
| `fix/` | バグ修正 | `fix/jwt-expiry-handling` |
| `refactor/` | 挙動を変えない整理 | `refactor/extract-auth-service` |
| `chore/` | 依存更新・設定・雑務 | `chore/bump-spring-boot` |
| `docs/` | ドキュメントのみ | `docs/setup-guide` |
| `test/` | テスト追加・修正 | `test/add-jwt-filter-tests` |

ブランチ名は `kebab-case`（小文字 + ハイフン）を使う。

### Step 3. 作業 & コミット

論理単位でコミットする。コミットメッセージは日本語でよい。

```bash
git add <files>
git commit -m "予算アラート機能の追加"
```

### Step 4. リモートに push

```bash
git push -u origin feat/budget-alert
```

### Step 5. PR を作成

```bash
gh pr create
```

PR を作成・更新すると GitHub Actions の `Analyze` と `Test` が並列に動く。通常は変更に関係するテストをローカルで優先し、失敗した CI はマージ前に修正する。

### Step 6. レビューする — 変更リスクで方式を選ぶ

変更内容を次の 3 段階に分けて、レビュー方式を選びます。**この表と直後の高リスク条件が、リスク判定の唯一の情報源です。** 高リスク条件を先に確認し、1 つでも該当すれば高リスク、該当しなければ通常とします。

| 段階 | レビュー方式 | 実行者 |
| --- | --- | --- |
| 軽微 | レビューなし（CI のみ） | — |
| 通常 | 別コンテキストのレビュアー 1 名（`/quick-review`） | Claude が自発起動してよい |
| 高リスク | 3 者独立レビュー（`/independent-review`） | ユーザーが明示的に実行する |

#### 高リスク条件

次のどれか 1 つでも該当する変更は、高リスクとして扱います。

- **DB スキーマ・マイグレーション**: `lib/db/database.dart` / `lib/db/database.g.dart` / `drift_schemas/**` / `test/generated_migrations/**` のいずれかに差分がある。`schemaVersion` の変更を含む場合は無条件で該当する
- **金額・集計・割り勘の計算**: `lib/db/summary_calculator.dart` / `lib/models/summary.dart` / `lib/models/split.dart` / `lib/models/transaction.dart` に差分がある。`lib/models/transaction.dart` の `kMaxAmount` は DB の CHECK 制約の根拠でもある
- **金額の整形**: `lib/widgets/amount_format.dart` に差分がある。`formatYen()` の書式を DB の整数 CHECK 制約が根拠にしている
- **既存データの削除・上書き**: `lib/db/database.dart` の `deleteTransaction` / `deleteCategory` / `deleteMember`、またはそれを呼ぶ Provider の `delete*` / `update*` を追加・変更する
- **プライバシー**: `lib/logging/log_entry.dart` の `sanitizeError`、または `OperationLogger` の `detail` に載せる値を追加・変更する。メモ本文と検索語をログに出さない約束に直結する
- **Dart SDK の下限**: `pubspec.yaml` の `environment.sdk` 下限を変更する。全 `.dart` ファイルの再整形を招くため、コード変更がなくても高リスクとする（`CLAUDE.md` の「コード整形」参照）

上記に該当しない `lib/**` / `test/**` のコード変更と、`.github/workflows/**` / `.claude/**` / `docs/**` / `README.md` / `CLAUDE.md` / `pubspec.yaml` / `pubspec.lock` の変更は通常です。ただし、意味を変えない Markdown 修正（typo、リンク切れ、表記ゆれ、整形）だけの差分と、高リスク条件に該当しない生成物の再生成だけで手書きコードに差分がない回は軽微です。軽微でも PR は作り、`.github/workflows/ci.yml` の `Analyze` / `Test` を従来どおり通します。

| コマンド | いつ使うか | 起動する人 | 手順の正本 |
| --- | --- | --- | --- |
| `/quick-review` | 通常リスクの変更を別コンテキストの 1 名でレビュー | Claude が自発起動してよい | [quick-review](../.claude/skills/quick-review/SKILL.md) |
| `/independent-review` | 高リスクの変更を観点別の 3 名でレビュー | ユーザーが明示的に実行 | [independent-review](../.claude/skills/independent-review/SKILL.md) |
| `/review <PR 番号>` | GitHub 上の PR をレビュー | ユーザー | — |
| `/code-review` | 手元の差分を軽量レビュー | ユーザー | — |
| `/code-review ultra` | 複数エージェントで多角レビュー（課金あり） | ユーザーが明示的に実行 | — |
| `/security-review` | セキュリティ観点でレビュー | ユーザー | — |

- `/code-review ultra` は課金が発生し、`/independent-review` は 3 体を同時起動するため、Claude 側から起動せずユーザーが明示する
- `/quick-review` と `/implement` は標準工程を自然文でも動かせるよう、Claude が自発起動してよい
- `.claude/agents/` や `.claude/skills/` を新規追加した直後は Claude Code の再起動が必要。一度監視下に入った `SKILL.md` の編集は再起動なしで反映される

指摘を直したら同じブランチへ再 push する。PR は自動で更新される。

### Step 7. squash merge + ブランチ削除

```bash
gh pr merge --squash --delete-branch
```

worktree から実行する場合と、子 PR が積み上がっている場合は経路が変わる。トラブルシューティングを参照するか、`/merge` を使う。

### Step 8. `main` を最新化

```bash
git switch main
git pull
```

## スキルで通す — `/implement` と `/merge`

| コマンド | 通す範囲 | 入力 | 起動する人 | 手順の正本 |
| --- | --- | --- | --- | --- |
| `/implement <issue 番号>` | Step 2〜5（ブランチ作成から PR 作成まで） | issue 番号 1 つ | Claude が自発起動してよい | [`.claude/skills/implement/SKILL.md`](../.claude/skills/implement/SKILL.md) |
| `/merge [PR 番号]` | Step 7〜8（squash merge から `main` 最新化・worktree 片付けまで） | PR 番号。省略時は現在のブランチの PR | ユーザーが明示的に実行 | [`.claude/skills/merge/SKILL.md`](../.claude/skills/merge/SKILL.md) |

`/merge` はユーザーが明示的に依頼したときだけ起動する。実装もレビューも修正もせず、落ちた CI も直さない。worktree の削除はユーザーが明示したときだけ行う。

## トラブルシューティング

### worktree から `gh pr merge` すると `'main' is already used by worktree at ...` エラー

Claude Code の worktree では親 worktree が `main` を使っているため、`gh pr merge` がローカルの `main` を checkout できない。GitHub REST API 経由でリモートだけマージし、親 worktree 側で `main` を更新する。

```bash
gh api -X PUT repos/<owner>/<repo>/pulls/<num>/merge -f merge_method=squash
gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>
git -C /path/to/parent pull --ff-only origin main
```

### 積み上げ PR の親をマージすると子 PR がクローズされる

子 PR の base が親ブランチのまま `gh api -X DELETE .../git/refs/heads/<親>` や `git push origin --delete <親>` で ref を消すと、子 PR は base が `main` へ付け替わるのではなくクローズされる。クローズ後は base が無いため `gh pr reopen` も `gh pr edit --base` も通らない。GitHub が自動で付け替えるのは `gh pr merge --delete-branch` と Web UI の Delete branch だけで、生の ref 削除はその経路を通らないため。

親を消す前に、先に子の base を付け替える。

```bash
gh pr edit <子PR> --base main     # 先にこれ
git push origin --delete <親ブランチ>
```

squash merge 運用なので、付け替えた子 PR は `main` と必ずコンフリクトする。付け替えたあと子ブランチを `main` へ rebase する作業が別途要る。

### worktree の活用

Claude Code は `.claude/worktrees/<name>/` に作業ディレクトリを作る。セッションごとに別ブランチを切り、`main` の作業と並行できる。
