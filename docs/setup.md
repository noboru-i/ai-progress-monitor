# セットアップガイド

AI Progress Monitor のセットアップ手順です。

---

## 1. アプリのビルド・起動

```bash
git clone https://github.com/noboru-i/otel-ai-monitor
cd otel-ai-monitor
open AIProgressMonitor.xcodeproj
```

Xcode で `⌘R` を押してビルド・起動してください。  
メニューバーに CPU アイコンが表示され、フローティングウィンドウが画面上に現れます。

---

## 2. フックスクリプトの配置

```bash
# 実行可能にして、任意の場所に配置
cp hooks/claude-code-hook.sh ~/Library/Application\ Support/AIProgressMonitor/hook.sh
chmod +x ~/Library/Application\ Support/AIProgressMonitor/hook.sh
```

---

## 3. Claude Code フックの設定

`~/.claude/settings.json` に以下を追加します（既存の `hooks` がある場合はマージしてください）。

```json
{
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "~/Library/Application Support/AIProgressMonitor/hook.sh"}]}],
    "PreToolUse":       [{"hooks": [{"type": "command", "command": "~/Library/Application Support/AIProgressMonitor/hook.sh"}]}],
    "PostToolUse":      [{"hooks": [{"type": "command", "command": "~/Library/Application Support/AIProgressMonitor/hook.sh"}]}],
    "Notification":     [
      {"matcher": "idle_prompt",       "hooks": [{"type": "command", "command": "~/Library/Application Support/AIProgressMonitor/hook.sh"}]},
      {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": "~/Library/Application Support/AIProgressMonitor/hook.sh"}]}
    ],
    "Stop":             [{"hooks": [{"type": "command", "command": "~/Library/Application Support/AIProgressMonitor/hook.sh"}]}],
    "SessionStart":     [{"hooks": [{"type": "command", "command": "~/Library/Application Support/AIProgressMonitor/hook.sh"}]}],
    "SessionEnd":       [{"hooks": [{"type": "command", "command": "~/Library/Application Support/AIProgressMonitor/hook.sh"}]}]
  }
}
```

設定後は Claude Code を再起動（または新しいセッションを開始）すると反映されます。

---

## 4. 動作確認

アプリが起動している状態で、以下のコマンドでテストデータを送信できます。

```bash
echo '{"session_id":"test-1","project_dir":"/Users/you/my-project","event":"PreToolUse","tool_name":"Bash","tool_detail":"npm test","model":null,"timestamp":'$(date +%s)'}' \
  | nc -U "$HOME/Library/Application Support/AIProgressMonitor/monitor.sock"
```

フローティングウィンドウに `my-project ⚙ Bash: npm test` と表示されれば成功です。

---

## 注意事項

- **ローカル完結**: Unix socket はローカルのみ。セッション内容が外部に送信されることはありません。
- **アプリ未起動時**: フックスクリプトはアプリが起動していない場合でも安全に `exit 0` します。Claude Code の動作をブロックしません。
