#!/usr/bin/env bash
# 開発用のダミー取引を、起動中の iOS シミュレータの DB へ投入する。
#
# アプリには含まれない開発専用のスクリプト。画面の見た目・集計・割り勘・
# フィルターを確認するときに、手入力の代わりに使う。
#
#   bash tool/seed_dev_data.sh              # 直近 12 か月ぶんを投入する
#   bash tool/seed_dev_data.sh --reset      # 既存の取引を消してから投入する
#   bash tool/seed_dev_data.sh --append     # 既存の取引を残したまま追記する
#   bash tool/seed_dev_data.sh --months 3   # 直近 3 か月ぶんにする
#   bash tool/seed_dev_data.sh --db PATH    # 投入先を明示する（シミュレータ以外）
#
# 既存の取引があるのに --reset も --append も無いときは、二重投入を避けて中止する。
set -euo pipefail

BUNDLE_ID="com.example.ledgerApp"
MONTHS="12"
DB_PATH=""
RESET=""
APPEND=""

while [ $# -gt 0 ]; do
  case "$1" in
    --reset) RESET="1"; shift ;;
    --append) APPEND="1"; shift ;;
    --months) MONTHS="${2:?--months には月数が要る}"; shift 2 ;;
    --db) DB_PATH="${2:?--db には sqlite ファイルのパスが要る}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "不明な引数: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$RESET" ] && [ -n "$APPEND" ]; then
  echo "--reset と --append は同時に指定できない" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

if [ -z "$DB_PATH" ]; then
  if ! CONTAINER="$(xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null)"; then
    echo "起動中のシミュレータに $BUNDLE_ID が見つからない。" >&2
    echo "先に flutter run でアプリを一度起動するか、--db でパスを指定すること。" >&2
    exit 1
  fi
  DB_PATH="$CONTAINER/Documents/ledgercore.sqlite"

  # 起動したままだとアプリが DB を掴んでいるので終了させる。
  # 起動していなくても失敗させない。
  xcrun simctl terminate booted "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo "投入先: $DB_PATH"

LEDGER_SEED_DB="$DB_PATH" \
LEDGER_SEED_MONTHS="$MONTHS" \
LEDGER_SEED_RESET="$RESET" \
LEDGER_SEED_APPEND="$APPEND" \
  flutter test tool/seed_dev_data.dart

echo
echo "投入が終わった。アプリを起動して確認する:"
echo "  xcrun simctl launch booted $BUNDLE_ID"
