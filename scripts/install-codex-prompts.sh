#!/bin/bash
# Codex CLI 用カスタムプロンプトの配備スクリプト
#
# Codex のカスタムプロンプトはユーザースコープ($CODEX_HOME/prompts)からのみ
# 読み込まれるため、リポジトリの .codex/prompts/ を配備する。
# 既存の同名ファイルは上書きする(正本はリポジトリ側)。

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src_dir="$repo_root/.codex/prompts"
dest_dir="${CODEX_HOME:-$HOME/.codex}/prompts"

if [ ! -d "$src_dir" ]; then
    echo "エラー: $src_dir が見つかりません" >&2
    exit 1
fi

mkdir -p "$dest_dir"
cp -v "$src_dir"/*.md "$dest_dir/"
echo "配備完了: $dest_dir(codex 内で /prompts 名で利用できます)"
