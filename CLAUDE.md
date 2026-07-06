# ai-support-kit(Claude Code 用プロジェクトメモリ)

共通インストラクションは以下を正本とする(Codex / Copilot と共有)。

@AGENTS.md

## Claude Code 固有の補足

- Skills(`.claude/skills/`)・スラッシュコマンド(`.claude/commands/`)・
  サブエージェント(`.claude/agents/`)は自動発見される。
- Hooks(`.claude/settings.json`)により、危険コマンドの遮断(PreToolUse)、
  変更系ツールの監査ログ記録(PostToolUse、`.audit/` 配下)、応答本文の検査
  (Stop、LLM judge・fail-open)が常時有効である。監査ログは
  作業管理システム連携を意識した作業証跡であり、削除しないこと。
- ログ解析は log-analyzer、仕様復元は spec-archaeologist、手順書・変更のレビューは
  safety-reviewer の各サブエージェントに委譲できる。
