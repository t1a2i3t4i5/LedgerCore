# AGENTS.md

このリポジトリで作業する Codex は、最初に [CLAUDE.md](CLAUDE.md) を読むこと。
ツール非依存の常時ルールと参照先は `CLAUDE.md` を正本とし、このファイルには複製しない。

## Codex 固有の補足

- `.codex/hooks.json` の `PostToolUse` フックは、`.dart` ファイルの編集後に `dart format` を実行する
- コミットの trailer は `Co-Authored-By: Codex Opus 5 <noreply@anthropic.com>`
- `.codex/agents/*.toml` と `.agents/skills` は生成物。正本を変更したら `tool/sync_codex_agents.sh` で再生成し、直接編集しない
