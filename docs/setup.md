# セットアップガイド

AI Progress Monitor のセットアップ手順です。

---

## 1. アプリのビルド・起動

```bash
git clone https://github.com/noboru-i/ai-progress-monitor
cd ai-progress-monitor
open AIProgressMonitor.xcodeproj
```

Xcode で `⌘R` を押してビルド・起動してください。  
メニューバーに CPU アイコンが表示され、フローティングウィンドウが画面上に現れます。

---

## 2. Claude Code のセットアップ

### 2-1. フックスクリプトの配置

```bash
# 実行可能にして、任意の場所に配置
cp hooks/claude-code-hook.sh ~/Library/Application\ Support/AIProgressMonitor/hook.sh
chmod +x ~/Library/Application\ Support/AIProgressMonitor/hook.sh
```

### 2-2. フックの設定

`~/.claude/settings.json` に以下を追加します（既存の `hooks` がある場合はマージしてください）。

```json
{
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "~/Library/Application\\ Support/AIProgressMonitor/hook.sh"}]}],
    "PreToolUse":       [{"hooks": [{"type": "command", "command": "~/Library/Application\\ Support/AIProgressMonitor/hook.sh"}]}],
    "PostToolUse":      [{"hooks": [{"type": "command", "command": "~/Library/Application\\ Support/AIProgressMonitor/hook.sh"}]}],
    "Notification":     [
      {"matcher": "idle_prompt",       "hooks": [{"type": "command", "command": "~/Library/Application\\ Support/AIProgressMonitor/hook.sh"}]},
      {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": "~/Library/Application\\ Support/AIProgressMonitor/hook.sh"}]}
    ],
    "Stop":             [{"hooks": [{"type": "command", "command": "~/Library/Application\\ Support/AIProgressMonitor/hook.sh"}]}],
    "SessionStart":     [{"hooks": [{"type": "command", "command": "~/Library/Application\\ Support/AIProgressMonitor/hook.sh"}]}],
    "SessionEnd":       [{"hooks": [{"type": "command", "command": "~/Library/Application\\ Support/AIProgressMonitor/hook.sh"}]}]
  }
}
```

設定後は Claude Code を再起動（または新しいセッションを開始）すると反映されます。

---

## 3. VS Code Copilot のセットアップ

### 3-1. フックスクリプトの配置

```bash
cp hooks/copilot-hook.sh ~/Library/Application\ Support/AIProgressMonitor/copilot-hook.sh
chmod +x ~/Library/Application\ Support/AIProgressMonitor/copilot-hook.sh
```

### 3-2. フック設定ファイルの配置

`hooks/copilot-hooks.json` を以下のいずれかにコピーしてください。

**グローバル設定（全プロジェクトに適用）:**

```bash
mkdir -p ~/.copilot/hooks
cp hooks/copilot-hooks.json ~/.copilot/hooks/ai-progress-monitor.json
```

**プロジェクト単位の設定:**

```bash
mkdir -p .github/hooks
cp hooks/copilot-hooks.json .github/hooks/ai-progress-monitor.json
```

設定後は VS Code を再起動すると反映されます。

### 3-3. Claude Code との差分・制限事項

| 機能 | Claude Code | VS Code Copilot |
|---|---|---|
| 思考中・ツール実行中の表示 | ✅ | ✅ |
| サブエージェント実行の表示 | - | ✅（Subagentとして表示） |
| 入力待ち・権限確認の表示 | ✅ | ❌（`Notification`イベントなし） |
| モデル名の表示 | ✅ | ❌（情報なし） |
| セッション自動削除 | ✅ | ❌（`Stop`後`.done`表示、上限20件で自動evict） |

