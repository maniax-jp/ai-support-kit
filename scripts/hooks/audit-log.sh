#!/bin/bash
# PostToolUse hook: 監査ログの記録
#
# ツール実行のたびに実行内容の要約を JSONL で追記する。
# 作業管理システム連携を意識した作業証跡であり、何を・いつ・どのセッションで
# 行ったかを後から追跡できるようにする。
#
# 出力先: $AISK_AUDIT_DIR(デフォルト: プロジェクト直下の .audit/)

# 注意: python3 のプログラムは -c で渡す。ヒアドキュメントを stdin に使うと
# hook 入力の JSON が読めなくなるため。
script=$(cat <<'PYEOF'
import json, os, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool_input = data.get("tool_input") or {}
# ツールごとに代表的な入力を要約として残す(全文は残さず肥大化を防ぐ)
summary = (
    tool_input.get("command")
    or tool_input.get("file_path")
    or tool_input.get("pattern")
    or ""
)

record = {
    "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
    "session_id": data.get("session_id", ""),
    "tool_name": data.get("tool_name", ""),
    "summary": str(summary)[:500],
    "cwd": data.get("cwd", ""),
}

audit_dir = os.environ.get("AISK_AUDIT_DIR") or os.path.join(
    data.get("cwd") or os.getcwd(), ".audit"
)
os.makedirs(audit_dir, exist_ok=True)
path = os.path.join(audit_dir, f"audit-{datetime.now():%Y%m%d}.jsonl")
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(record, ensure_ascii=False) + "\n")

sys.exit(0)
PYEOF
)

exec python3 -c "$script"
