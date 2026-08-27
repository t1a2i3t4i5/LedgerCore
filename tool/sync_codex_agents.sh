#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

skills_link=.agents/skills
skills_target=../.claude/skills
agents_source=.claude/agents
agents_output=.codex/agents

if [[ ! -d $agents_source ]]; then
  echo "入力ディレクトリがありません: $agents_source" >&2
  exit 1
fi

if [[ -L $skills_link && $(readlink "$skills_link") == "$skills_target" ]]; then
  :
else
  rm -rf -- "$skills_link"
  mkdir -p "$(dirname "$skills_link")"
  ln -s "$skills_target" "$skills_link"
fi

mkdir -p "$agents_output"
staging_dir=$(mktemp -d ".codex/.agents-sync.XXXXXX")
body_file=
trap 'rm -f -- "$body_file"; rm -rf -- "$staging_dir"' EXIT

shopt -s nullglob
agent_files=("$agents_source"/*.md)
if (( ${#agent_files[@]} == 0 )); then
  echo "エージェント定義がありません: $agents_source/*.md" >&2
  exit 1
fi

for source_file in "${agent_files[@]}"; do
  if [[ $(sed -n '1p' "$source_file") != '---' ]]; then
    echo "frontmatter の開始行がありません: $source_file" >&2
    exit 1
  fi

  frontmatter_end=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$source_file")
  if [[ -z $frontmatter_end ]]; then
    echo "frontmatter の終了行がありません: $source_file" >&2
    exit 1
  fi

  name=$(sed -n "2,$((frontmatter_end - 1))p" "$source_file" | sed -n 's/^name:[[:space:]]*//p')
  description=$(sed -n "2,$((frontmatter_end - 1))p" "$source_file" | sed -n 's/^description:[[:space:]]*//p')
  effort=$(sed -n "2,$((frontmatter_end - 1))p" "$source_file" | sed -n 's/^effort:[[:space:]]*//p')

  if [[ -z $name || -z $description || -z $effort ]]; then
    echo "name、description、effort のいずれかがありません: $source_file" >&2
    exit 1
  fi

  body_file=$(mktemp)
  sed -n "$((frontmatter_end + 1)),\$p" "$source_file" > "$body_file"

  if grep -Fq '\' "$body_file"; then
    echo "本文にバックスラッシュが含まれています: $source_file" >&2
    exit 1
  fi
  if grep -Fq '"""' "$body_file"; then
    echo "本文に三重引用符が含まれています: $source_file" >&2
    exit 1
  fi

  escaped_name=${name//\\/\\\\}
  escaped_name=${escaped_name//\"/\\\"}
  escaped_description=${description//\\/\\\\}
  escaped_description=${escaped_description//\"/\\\"}
  escaped_effort=${effort//\\/\\\\}
  escaped_effort=${escaped_effort//\"/\\\"}
  output_file="$staging_dir/$name.toml"

  {
    printf 'name = "%s"\n' "$escaped_name"
    printf 'description = "%s"\n' "$escaped_description"
    printf 'model_reasoning_effort = "%s"\n' "$escaped_effort"
    printf 'developer_instructions = """\n'
    cat "$body_file"
    printf '"""\n'
  } > "$output_file"

  rm -f -- "$body_file"
  body_file=
done

find "$agents_output" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
generated_files=("$staging_dir"/*.toml)
mv -- "${generated_files[@]}" "$agents_output/"
rm -rf -- "$staging_dir"
staging_dir=
trap - EXIT

echo "Codex 設定を同期しました（スキル: ${skills_link}、エージェント: ${#agent_files[@]} 件）"
