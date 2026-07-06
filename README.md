# ai-support-kit

AI サポートキット

## 準備物の構成

本リポジトリには Claude Code / Codex / GitHub Copilot で使用できる以下の準備物が含まれる。

### Skills(3ツール共通・Agent Skills 標準)

正本は `.claude/skills/`。`.codex/skills` と `.github/skills` はシンボリックリンクで同一実体を参照する。

| Skill | 用途 |
|---|---|
| telecom-log-analysis | 設備ログの解析・時系列相関・原因推定 |
| kpi-degradation-analysis | KPI 劣化の検出・影響範囲・要因分析 |
| param-audit | パラメータダンプの差分監査・変更票作成 |
| spec-recovery | コード/ログ/日誌からの仕様復元(リファレンス文書生成) |
| work-procedure | 作業手順書(事前確認・投入・事後確認・切り戻し)の生成 |
| incident-report | 障害報告書の作成 |

### インストラクション・コマンド・エージェント・Hooks

| 準備物 | Claude Code | Codex | Copilot |
|---|---|---|---|
| 共通インストラクション | `CLAUDE.md`(`AGENTS.md` をインポート) | `AGENTS.md` | `AGENTS.md` / `.github/copilot-instructions.md` |
| スラッシュコマンド | `.claude/commands/` | `.codex/prompts/`(要インストール※) | `.github/prompts/` |
| サブエージェント | `.claude/agents/` | — | `.github/agents/` |
| Hooks | `.claude/settings.json` + `scripts/hooks/` | — | — |

※ Codex のカスタムプロンプトはユーザースコープのみのため `./scripts/install-codex-prompts.sh` で `~/.codex/prompts` に配備する。

コマンドは `/analyze-logs` `/kpi-report` `/param-diff` `/gen-procedure` `/incident-report` `/recover-spec` の 6 種。
エージェントは log-analyzer(ログ解析)、spec-archaeologist(仕様復元)、safety-reviewer(安全性レビュー)の 3 種。

Hooks は PreToolUse で危険コマンド(破壊的操作・一括投入の疑い)を遮断し、PostToolUse で作業証跡を `.audit/`(gitignore 対象)に JSONL 記録する。遮断パターンは環境変数 `AISK_BLOCK_PATTERNS_FILE`、監査ログ出力先は `AISK_AUDIT_DIR` で変更できる。

### サンプルデータ(`samples/`)

動作確認用。「6/30 夜間のパラメータ変更 → 7/1 以降の KPI 劣化 → ログのアラーム → 日誌の記録」という一貫したシナリオを持つ設備ログ・KPI・パラメータ新旧版・オペレータ日誌。

## インストール

### 前提条件

- git および python3(hooks が使用。macOS / Linux では標準搭載)
- 使用する CLI がインストール・認証済みであること: `claude`(Claude Code)/ `codex`(Codex CLI)/ `copilot`(GitHub Copilot CLI)のいずれか(複数可)

### 手順

1. **リポジトリを clone する**

   ```bash
   git clone <このリポジトリのURL>
   cd ai-support-kit
   ```

   スキルの共有にシンボリックリンク(`.codex/skills`、`.github/skills` → `.claude/skills`)を
   使用している。Windows で利用する場合は clone 前に `git config --global core.symlinks true` を
   設定し、開発者モードを有効にすること。

2. **Claude Code** — 追加作業なし。リポジトリ内で `claude` を起動すれば Skills / コマンド /
   エージェント / Hooks がすべて有効になる。初回起動時にプロジェクト設定(`.claude/settings.json`
   の hooks)の信頼確認が表示されるので内容を確認して承認する。

3. **Codex** — Skills は追加作業なし(リポジトリスコープで自動発見)。スラッシュコマンド
   (カスタムプロンプト)も使う場合のみ、配備スクリプトを実行する:

   ```bash
   ./scripts/install-codex-prompts.sh   # ~/.codex/prompts へコピー
   ```

4. **GitHub Copilot** — 追加作業なし。`AGENTS.md`、`.github/copilot-instructions.md`、
   `.github/skills/`、`.github/prompts/`、`.github/agents/` が自動発見される。

5. **動作確認** — 以下の 3 コマンドで各 CLI がスキルを認識することを確認する:

   ```bash
   # Claude Code(スラッシュコマンド+スキル)
   claude -p "/analyze-logs samples/logs/enodeb.log"

   # Codex(リポジトリスコープのスキル)
   codex exec --sandbox read-only "kpi-degradation-analysis スキルに従って samples/kpi/daily_kpi.csv を分析して"

   # Copilot(スキル+エージェント)
   copilot -p "param-audit スキルに従い samples/params/cell_params_v1.csv と cell_params_v2.csv を監査して" --allow-all-tools
   ```

   3 コマンドとも上記の方法でスキルの認識・手順への追従を確認済み(2026-07-06)。

### 個人ごとのカスタマイズ

- `.claude/settings.local.json` は個人用設定であり git 管理されない(チーム共有設定は `settings.json`)。
- Hooks の遮断パターン追加は環境変数 `AISK_BLOCK_PATTERNS_FILE`(1 行 1 正規表現のファイルを指定)、
  監査ログの出力先変更は `AISK_AUDIT_DIR` で行う。

## ユースケース例

本キットは「業務フロー改革」「システム刷新」「通信システムシミュレーション環境構築」の
3 つの目的に向けた足場として使う。

### 1. 業務フロー改革

属人化した運用知識の可視化と、「AI が生成し、機械的にレビューし、人が承認する」フローへの転換に使う。

- **暗黙知の文書化**: オペレータ日誌・作業票を `/recover-spec`(spec-recovery)に渡し、
  文書化されていない運用ルール・ワークアラウンドをリファレンス化する。確度ラベル付きで
  出力されるため、そのまま業務標準化の審議資料になる。
- **変更管理フローの雛形**: `/gen-procedure` で切り戻し付き手順書を生成し、safety-reviewer
  エージェントに機械レビューさせてから人が承認する。「判断と実行の分離」を前提にした
  新しい変更管理フローとして展開できる。
- **振り返りの定型化**: 障害のたびに `/incident-report` でログ・KPI・日誌から報告書を生成し、
  再発防止策を「精神論でなく仕組み」で書かせることを標準にする。
- **作業証跡の自動化**: Hooks の監査ログ(`.audit/`)は AI が行った操作の証跡であり、
  作業管理システムとの突き合わせ・監査対応の土台になる。

### 2. システム刷新

リファレンスドキュメントがない独自システム群を、仕様を失わずに刷新するために使う。

- **現行仕様の復元**: 刷新対象システムのソースコード・ログ・日誌を spec-archaeologist
  エージェント(`/recover-spec`)に渡し、リファレンスを復元する。復元文書の「未解明事項」が
  そのまま刷新要件定義で潰すべき論点リストになる。
- **移行の同値性監査**: 新旧システムが出力するパラメータ・設定を `/param-diff`(param-audit)で
  機械的に比較し、移行漏れ・意図外差分を検出する。受け入れ試験の合否判定に使える。
- **並行運用の監視**: 新旧並行運用期間中のログを `/analyze-logs`、KPI を `/kpi-report` で
  継続的に比較し、刷新起因の劣化を早期検出する。

### 3. 通信システムシミュレーション環境構築

「本番を模擬する環境が用意できない」制約を、フィールドデータ駆動のシミュレーションで補うために使う。

- **再現シナリオの抽出**: 実フィールドのログ(`/analyze-logs`)と KPI(`/kpi-report`)から
  劣化イベントの時系列・波及パターンを抽出し、シミュレータが再現すべきシナリオ仕様に変換する。
- **検証データセットの整備**: `samples/` は「パラメータ変更 → KPI 劣化 → アラーム → 日誌」の
  一貫シナリオを持つデータセットの雛形である。実データから同形式のシナリオを蓄積し、
  シミュレータおよび AI 自動化パイプラインの回帰テストに使う。
- **投入前検証フローへの組み込み**: `/gen-procedure` が生成する手順書の「事前確認」に
  シミュレーションによる検証を組み込み、`/param-diff` の監査と合わせて
  「シミュレーションで事前検証してから段階投入する」フローを標準化する。