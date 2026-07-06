#!/bin/bash
# PreToolUse hook: 危険コマンドの遮断
#
# stdin に Claude Code から hook 入力(JSON)が渡される。
# Bash ツールのコマンドが危険パターンに一致した場合、exit 2 でブロックし
# 理由を stderr に出力する(stderr はエージェントへのフィードバックになる)。
#
# 追加パターンは環境変数 AISK_BLOCK_PATTERNS_FILE で指定したファイル
# (1 行 1 正規表現、# 始まりはコメント)で拡張できる。

# 注意: python3 のプログラムは -c で渡す。ヒアドキュメントを stdin に使うと
# hook 入力の JSON が読めなくなるため。
script=$(cat <<'PYEOF'
import json, os, re, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)  # 入力が解釈できない場合は妨げない

command = (data.get("tool_input") or {}).get("command") or ""
if not command:
    sys.exit(0)

# デフォルトの危険パターン(破壊的操作・本番一括投入の示唆)
patterns = [
    # 安全規範(AGENTS.md)は再帰的削除そのものを禁じるため、対象パスに
    # よらず遮断する(必要な削除は非再帰で個別に行うか、人が行う)
    (r"\brm\s+(\S+\s+)*(-\w*[rR]\w*|--recursive)(\s|$)", "再帰的削除(rm -r 系)"),
    (r"\bmkfs(\.|\s)", "ファイルシステム作成(ディスク破壊)"),
    (r"\bdd\b.*\bof=/dev/", "デバイスへの直接書き込み"),
    (r"git\s+push\s+.*(--force|-f)\b.*\b(main|master)\b", "保護ブランチへの強制 push"),
    (r"(bulk|batch|一括)[-_ ]?(activate|apply|provision|投入|活性)", "設備への一括投入・活性化の疑い"),
]

# 環境変数で追加パターンを読み込む
extra = os.environ.get("AISK_BLOCK_PATTERNS_FILE")
if extra and os.path.isfile(extra):
    with open(extra, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                patterns.append((line, "追加ブロックパターン"))

for pattern, reason in patterns:
    try:
        if re.search(pattern, command, re.IGNORECASE):
            print(
                f"ブロック: このコマンドは安全規範に抵触します({reason})。"
                f"パターン: {pattern}",
                file=sys.stderr,
            )
            sys.exit(2)
    except re.error:
        continue  # 不正な正規表現は無視する

sys.exit(0)
PYEOF
)

exec python3 -c "$script"
