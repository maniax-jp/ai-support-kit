#!/bin/bash
# hooks の動作確認(smoke test)
#
# LLM・ネットワークに依存せず、スタブ judge と偽 transcript を使って
# 3 つの hook(precheck / audit-log / stop-llm-judge)の判定経路を再現する。
# README の「動作確認」を第三者が再現するためのスクリプト。
#
# 使い方:
#   ./scripts/smoke-hooks.sh           # 全 hook の判定経路を確認
#   ./scripts/smoke-hooks.sh --judge   # 加えて Stop hook の実 judge backend の疎通を確認
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

check_exit() { # $1=テスト名 $2=期待 exit $3=実際 exit
    if [ "$2" -eq "$3" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $1"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $1(期待 exit=$2 実際 exit=$3)"
    fi
}

check_true() { # $1=テスト名 $2=直前コマンドの exit(0 なら成功)
    if [ "$2" -eq 0 ]; then
        PASS=$((PASS + 1)); echo "  PASS: $1"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $1"
    fi
}

# ---------------------------------------------------------------------------
echo "== precheck.sh(危険コマンド遮断)=="
run_precheck() {
    printf '{"tool_input":{"command":"%s"}}' "$1" \
        | bash "$ROOT/scripts/hooks/precheck.sh" >/dev/null 2>&1
    echo $?
}
check_exit "rm -rf / を遮断" 2 "$(run_precheck 'rm -rf /')"
check_exit "rm -rf /tmp/test を遮断" 2 "$(run_precheck 'rm -rf /tmp/test')"
check_exit "rm -r build(相対パス)を遮断" 2 "$(run_precheck 'rm -r build')"
check_exit "rm --recursive dir を遮断" 2 "$(run_precheck 'rm --recursive dir')"
check_exit "rm -f -r dir(フラグ分離)を遮断" 2 "$(run_precheck 'rm -f -r dir')"
check_exit "main への強制 push を遮断" 2 "$(run_precheck 'git push --force origin main')"
check_exit "rm 単一ファイル(非再帰)は許可" 0 "$(run_precheck 'rm build/output.txt')"
check_exit "ls -la は許可" 0 "$(run_precheck 'ls -la')"

# ---------------------------------------------------------------------------
echo "== audit-log.sh(監査ログ記録)=="
(
    unset AISK_AUDIT_DIR
    export CLAUDE_PROJECT_DIR="$TMP/proj"
    printf '{"session_id":"smoke","tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"%s"}' "$TMP/elsewhere" \
        | bash "$ROOT/scripts/hooks/audit-log.sh"
)
ls "$TMP/proj/.audit"/audit-*.jsonl >/dev/null 2>&1
check_true "cwd がサブディレクトリでも CLAUDE_PROJECT_DIR 直下の .audit/ に記録" $?
(
    export AISK_AUDIT_DIR="$TMP/audit-custom"
    printf '{"session_id":"smoke","tool_name":"Write","tool_input":{"file_path":"a.txt"}}' \
        | bash "$ROOT/scripts/hooks/audit-log.sh"
)
grep -q '"tool_name": "Write"' "$TMP/audit-custom"/audit-*.jsonl 2>/dev/null
check_true "AISK_AUDIT_DIR への出力と実行内容の記録" $?

# ---------------------------------------------------------------------------
echo "== stop-llm-judge.sh(応答本文の 2 段判定)=="
cat > "$TMP/transcript-violation.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"バグを直してください"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"修正を実装したので、次の作業として commit しましょう。"}]}}
EOF
cat > "$TMP/transcript-bypass.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"バグを直してください"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"テスト実行 rc=0 を確認しました。commit しますか?"}]}}
EOF
# スタブ judge: violation 相当の JSON を返す(LLM 不要で判定経路を再現)
cat > "$TMP/stub-violation.sh" <<'EOF'
#!/bin/bash
cat > /dev/null
echo '{"new_proposal": true, "verification_reported": false, "direction_query": false, "future_step_description": false, "reason": "検証報告なしの commit 提案"}'
EOF
# スタブ judge: 故障(fail-open の確認用)
cat > "$TMP/stub-broken.sh" <<'EOF'
#!/bin/bash
cat > /dev/null
exit 1
EOF
chmod +x "$TMP/stub-violation.sh" "$TMP/stub-broken.sh"

run_stop() { # $1=transcript $2=judge_cmd $3=stop_hook_active
    printf '{"session_id":"smoke","transcript_path":"%s","stop_hook_active":%s}' "$1" "$3" \
        | env AISK_JUDGE_CMD="$2" AISK_JUDGE_LOG_DIR="$TMP/logs" \
              bash "$ROOT/scripts/hooks/stop-llm-judge.sh" >/dev/null 2>&1
    echo $?
}
check_exit "検証実証なしの commit 提案を block(exit 2)" 2 \
    "$(run_stop "$TMP/transcript-violation.jsonl" "$TMP/stub-violation.sh" false)"
check_exit "検証実証つき(rc=0)は Layer 1 bypass で許可" 0 \
    "$(run_stop "$TMP/transcript-bypass.jsonl" "$TMP/stub-broken.sh" false)"
check_exit "judge 故障時は fail-open で許可" 0 \
    "$(run_stop "$TMP/transcript-violation.jsonl" "$TMP/stub-broken.sh" false)"
check_exit "stop_hook_active 時は再検査しない(ループ防止)" 0 \
    "$(run_stop "$TMP/transcript-violation.jsonl" "$TMP/stub-violation.sh" true)"
rc=$(printf '{"session_id":"smoke","transcript_path":"%s","stop_hook_active":false}' "$TMP/transcript-violation.jsonl" \
    | STOP_HOOK_LLM_JUDGE_ACTIVE=1 bash "$ROOT/scripts/hooks/stop-llm-judge.sh" >/dev/null 2>&1; echo $?)
check_exit "再帰ガード(STOP_HOOK_LLM_JUDGE_ACTIVE=1)で即許可" 0 "$rc"

# ---------------------------------------------------------------------------
# --judge: 実 backend の疎通確認(こちらは LLM 呼び出しが発生する)
if [ "${1:-}" = "--judge" ]; then
    echo "== judge backend 疎通確認 =="
    cmd="${AISK_JUDGE_CMD:-claude -p --model claude-haiku-4-5-20251001}"
    echo "  backend: $cmd"
    out=$(printf '{"ok": true} という JSON を 1 行だけ返してください。' \
        | STOP_HOOK_LLM_JUDGE_ACTIVE=1 sh -c "$cmd" 2>&1)
    case "$out" in
        *'"ok"'*) check_true "backend が JSON を返す" 0 ;;
        *)
            echo "  出力(先頭 3 行): $(printf '%s' "$out" | head -3)"
            check_true "backend が JSON を返す" 1
            ;;
    esac
    echo "  ※ 疎通に失敗している間、Stop hook は fail-open(検査なし素通し)になる。"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
