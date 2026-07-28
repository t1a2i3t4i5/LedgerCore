# git 運用ガイド

このリポジトリでの git 運用方針と、日常的な開発フローをまとめたガイドです。

## 運用方針

- **GitHub Flow** を採用
- `main` は常にデプロイ可能な状態を保つ(直接 push しない)
- 機能・修正ごとにブランチを切る
- PR を作成して **Claude にレビュー** させる
- マージは **squash merge + ブランチ自動削除**

## 事前準備

### 1. GitHub CLI (`gh`) のインストール

PR の作成やマージをターミナルから完結させるため、GitHub 公式の CLI ツールを使います。

```bash
# Homebrew (macOS)
brew install gh
```

その他のインストール方法は [公式サイト](https://cli.github.com/) を参照。

### 2. 認証

```bash
gh auth login
```

対話形式で以下を選択します。

| 質問                                  | 推奨回答                |
| ------------------------------------- | ----------------------- |
| What account do you want to log into? | `GitHub.com`            |
| Preferred protocol for Git operations | `HTTPS`                 |
| Authenticate Git with your credentials? | `Yes`                 |
| How would you like to authenticate?   | `Login with a web browser` |

ブラウザが開くので、表示される 8 桁のコードを入力して認可します。

### 3. リポジトリのクローン(初回のみ)

```bash
git clone <このリポジトリの URL>
cd Ledger
```

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

| プレフィックス | 用途                       | 例                              |
| -------------- | -------------------------- | ------------------------------- |
| `feat/`        | 新機能                     | `feat/budget-alert`             |
| `fix/`         | バグ修正                   | `fix/jwt-expiry-handling`       |
| `refactor/`    | 挙動を変えない整理         | `refactor/extract-auth-service` |
| `chore/`       | 依存更新・設定・雑務       | `chore/bump-spring-boot`        |
| `docs/`        | ドキュメントのみ           | `docs/setup-guide`              |
| `test/`        | テスト追加・修正           | `test/add-jwt-filter-tests`     |

ブランチ名は `kebab-case`(小文字 + ハイフン)を使うこと。

### Step 3. 作業 & コミット

論理単位で小さくコミットすると、後で `git revert` しやすくなります。

```bash
git add <files>
git commit -m "予算アラート機能の追加"
```

コミットメッセージは日本語で OK。Claude Code に「コミットして」と頼めば、差分を見てメッセージを書いてくれます。

### Step 4. リモートに push

```bash
git push -u origin feat/budget-alert
```

`-u` で upstream を設定しておくと、以降は `git push` だけで済みます。

### Step 5. PR を作成

```bash
gh pr create
```

エディタが開くのでタイトルと本文を記入して保存します。引数で渡すこともできます。

```bash
gh pr create --title "予算アラート機能の追加" --body "..."
```

### Step 6. Claude にレビューさせる

Claude Code 内で次のスラッシュコマンドを実行します。

| コマンド              | 用途                                       |
| --------------------- | ------------------------------------------ |
| `/review <PR 番号>`   | GitHub 上の PR をレビュー                  |
| `/code-review`        | 手元の作業差分を軽量レビュー(コード品質・可読性) |
| `/code-review ultra`  | 多角的レビュー(複数エージェントによるクラウドレビュー、課金あり) |
| `/security-review`    | セキュリティ観点のレビュー                 |

`/code-review ultra` は引数なしで現在のブランチ全体、`/code-review ultra <PR 番号>` で GitHub 上の PR を対象にできます。課金が発生するためユーザー自身が実行する必要があり、Claude 側から起動することはできません。

> かつての `/ultrareview` は `/code-review ultra` の非推奨エイリアスです。新しく書く場合は `/code-review ultra` を使ってください。

指摘されたら修正して再 push します。同じブランチに push すれば PR は自動的に更新されます。

### Step 7. squash merge + ブランチ削除

```bash
gh pr merge --squash --delete-branch
```

- `--squash`: ブランチのコミットを 1 つにまとめて `main` に乗せる
- `--delete-branch`: マージ後にローカル & リモートの両方のブランチを削除

### Step 8. `main` を最新化

```bash
git switch main
git pull
```

これで次の作業に入れます。

## マージ方式の比較

`feat` ブランチに 3 コミット (`A` → `B` → `C`) があった場合の `main` の履歴の見え方を比較します。

```
--merge (デフォルト)        ← マージコミットが残る
  main: ... ─┬─ A ─ B ─ C ─┐
             └─────────────M (Merge commit)

--squash  ★このプロジェクトの基本
  main: ... ─ ABC          ← 3 コミットが 1 つに潰れる

--rebase
  main: ... ─ A ─ B ─ C    ← マージコミット無しで直列に並ぶ
```

| 方式       | メリット                              | デメリット                         |
| ---------- | ------------------------------------- | ---------------------------------- |
| `--merge`  | ブランチでの作業履歴が全部残る        | `main` の履歴が複雑になる          |
| `--squash` | `main` が「PR 1 つ = 1 コミット」で綺麗、revert が楽 | ブランチ内の細かいコミット履歴が失われる |
| `--rebase` | マージコミット無しで直列の歴史        | "wip" などの中間コミットが `main` に残る |

個人開発・小規模チームでは **`--squash` が最もおすすめ** です。

## よく使う `gh` コマンド

```bash
gh pr list                       # 自分のリポジトリの PR 一覧
gh pr view <num>                 # PR の詳細表示
gh pr view <num> --web           # PR をブラウザで開く
gh pr checkout <num>             # PR のブランチにローカルで切り替え
gh pr status                     # 自分が関わる PR の状況
gh pr comment <num> --body "LGTM" # PR にコメント
gh pr diff <num>                 # PR の差分を表示

gh issue list                    # Issue 一覧
gh issue view <num>              # Issue 詳細
gh issue create                  # Issue 作成

gh repo view --web               # リポジトリをブラウザで開く
```

## トラブルシューティング

### `git push` が rejected された

`main` が他の PR で進んでいる場合に発生します。リモートの変更を取り込んでから再 push します。

```bash
git pull --rebase origin main
git push
```

### `gh pr merge` の squash オプションでエラー

リポジトリで squash merge が許可されていない可能性があります。GitHub 上で次の手順で有効化してください。

`Settings` → `General` → `Pull Requests` → `Allow squash merging` にチェック

### worktree から `gh pr merge` すると `'main' is already used by worktree at ...` エラー

Claude Code の worktree(`.claude/worktrees/<name>/`)から `gh pr merge` を実行すると、`gh` がローカルの main を更新するために `git checkout main` を試みますが、main が親 worktree で使用中のため失敗します。

```
failed to run git: fatal: 'main' is already used by worktree at '/path/to/parent'
```

この場合、GitHub REST API 経由でリモートだけマージし、ローカル main の更新は親 worktree 側で別途実行します。

```bash
# リモートのみ squash merge
gh api -X PUT repos/<owner>/<repo>/pulls/<num>/merge -f merge_method=squash

# リモートブランチを削除
gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>

# 親 worktree 側で main を fast-forward
git -C /path/to/parent pull --ff-only origin main
```

### `--delete-branch` してもローカルのブランチが残る

`gh pr merge --delete-branch` はリモート側を確実に消しますが、ローカル側は削除に失敗するケースもあります。手動で消します。

```bash
git switch main
git branch -d feat/budget-alert    # マージ済みなら -d で消える
git branch -D feat/budget-alert    # 強制削除(未マージのコミットがある場合)
```

### `gh pr create` で `no upstream branch` エラー

ブランチをまだ push していない状態です。先に upstream 付きで push します。

```bash
git push -u origin <branch-name>
```

### 間違ったブランチでコミットしてしまった

まだ push していなければ、新しいブランチに移して取り消せます。

```bash
git switch -c feat/correct-branch  # 正しいブランチを作成(変更は引き継がれる)
git switch -                       # 元のブランチに戻る
git reset --hard origin/main       # 元のブランチをリモート main にリセット
git switch feat/correct-branch     # 正しいブランチに戻って作業継続
```

`git reset --hard` は破壊的な操作なので、元のブランチに残したい変更がないか確認してから実行してください。

## Claude Code との連携 Tips

### worktree の活用

Claude Code は `.claude/worktrees/<name>/` 配下にブランチごとの作業ディレクトリを作る `worktree` 機能を持ちます。`main` で作業しつつ別ブランチも並行で進められるので、Claude のセッションごとに別ブランチを切って作業させられます。

### コミットの作成

「コミットして」と頼めば、Claude は `git status` と `git diff` を見て、日本語のコミットメッセージを書いてコミットします。明示的に頼まない限り Claude は勝手にコミットしません。

### スケジュール機能

`/schedule` コマンドで、未来に Claude エージェントを走らせる予約ができます。たとえば「2 週間後にこのフィーチャーフラグの掃除 PR を開く」「毎週月曜にステール PR を triage する」などの使い方が可能です。

### `CLAUDE.md` の参照

このドキュメントは `CLAUDE.md` から参照されており、Claude が git 操作を頼まれた際に自動で内容を読み込みます。ルールを変更した場合はこのファイルを更新するだけで Claude の挙動にも反映されます。
