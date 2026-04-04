# AI Progress Monitor

## プロジェクト概要

Claude Code の hooks を使って AI の状態をリアルタイム監視し、  
「どのプロジェクトで・AIが何をしているか・そこから何秒経過しているか」を  
**常に最前面に浮かぶ小さなウィンドウ**に表示し続けるMacアプリ。

---

## アーキテクチャ

```
Claude Code ──(hooks: command)──→ hooks/claude-code-hook.sh
                                        │
                               stdin JSON + CLAUDE_PROJECT_DIR
                                        │
                               Unix domain socket (AF_UNIX)
                                        ↓
                            HookSocketServer（macOSアプリ内）
                                        ↓
                                   StatusStore
                                   （状態管理）
                                        ↓
                               FloatingWindow（SwiftUI）
                               NSWindow.level = .floating
```

---

## ファイル構成

```
OtelAIMonitor/
├── OtelAIMonitorApp.swift    # エントリーポイント・NSWindowセットアップ
├── HookSocketServer.swift    # Unix socketサーバー・HookEvent定義
├── StatusStore.swift         # セッション状態管理（ObservableObject）
├── FloatingWindowView.swift  # 浮きウィンドウのSwiftUI View
├── MenuBarView.swift         # メニューバーPopover
└── Models.swift              # SessionState / Status 定義

hooks/
└── claude-code-hook.sh       # Claude Codeフック用スクリプト
```

---

## Unix socket パス

`~/Library/Application Support/AIProgressMonitor/monitor.sock`

---

## hooks セットアップ（~/.claude/settings.json）

```json
{
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
    "PreToolUse":       [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
    "PostToolUse":      [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
    "Notification":     [{"matcher": "idle_prompt", "hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
    "Stop":             [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
    "SessionStart":     [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
    "SessionEnd":       [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}]
  }
}
```

---

## テスト用（ソケットに直接送信）

```bash
# アプリ起動後
echo '{"session_id":"test-1","project_dir":"/Users/you/my-project","event":"PreToolUse","tool_name":"Bash","tool_detail":"npm test","model":null,"timestamp":'$(date +%s)'}' \
  | nc -U "$HOME/Library/Application Support/AIProgressMonitor/monitor.sock"
```

---

## 注意事項・制約

- **ローカル完結**: Unix socketはローカルのみ。外部送信なし
- **プロジェクト名**: `CLAUDE_PROJECT_DIR` の basename を表示
- **入力待ち検知**: `Notification(idle_prompt)` フックで明示的に検知（タイマー推定不要）
- **ウィンドウ操作**: `isMovableByWindowBackground = true` でドラッグ移動可
- **Copilot対応**: 現時点では未対応（VS Code hooksが整備され次第追加予定）
