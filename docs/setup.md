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

---

## 4. Codex CLI のセットアップ

### 4-1. フックスクリプトの配置

```bash
cp hooks/codex-hook.sh ~/Library/Application\ Support/AIProgressMonitor/codex-hook.sh
chmod +x ~/Library/Application\ Support/AIProgressMonitor/codex-hook.sh
```

### 4-2. フック設定ファイルの配置

`hooks/codex-hooks.json` を以下のいずれかにコピーしてください。

**グローバル設定（全プロジェクトに適用）:**

```bash
cp hooks/codex-hooks.json ~/.codex/hooks.json
```

`~/.codex/hooks.json` が既に存在する場合は、中身をマージしてください
（同一レイヤーに `hooks.json` と `config.toml` の `[hooks]` テーブルが両方存在すると、
Codexは両方を読み込んだ上で警告を表示します）。

**プロジェクト単位の設定:**

```bash
mkdir -p .codex
cp hooks/codex-hooks.json .codex/hooks.json
```

### 4-3. フックの信頼（Hook Trust）

Codexは非管理（unmanaged）のフックを初回実行時にレビュー・承認する必要があります。
インタラクティブセッションでは `/hooks` コマンドから有効化・確認できます。
設定後は新しいセッションを開始すると反映されます。

### 4-4. Claude Code との差分・制限事項

| 機能 | Claude Code | Codex CLI |
|---|---|---|
| 思考中・ツール実行中の表示 | ✅ | ✅ |
| サブエージェント実行の表示 | - | -（`SubagentStart`/`SubagentStop`は未対応） |
| 入力待ちの表示 | ✅（`Notification: idle_prompt`） | ❌（相当するイベントなし。`toolRunning`が一定時間続くと`stalled`表示で代替） |
| 権限確認の表示 | ✅ | ✅（`PermissionRequest`イベント。承認/PreToolUse系は動作未実測、公式ドキュメントに基づく実装） |
| モデル名の表示 | ✅ | ✅（`SessionStart`/`UserPromptSubmit`/`SessionEnd`で実測確認済み） |
| セッション自動削除 | ✅ | ✅（`SessionEnd`発火を実測確認済み。timeoutは3秒にクランプされる。念のため上限20件の自動evictもフォールバックとして機能） |

補足:
- Codexのフックは `tool_name`/`tool_input` のスキーマが今後拡張される可能性があります
  （現時点ではシェル実行系のツールが中心）。`hooks/codex-hook.sh` は `tool_input.command` /
  `file_path` / `path` を優先的に拾い、配列やその他の型が来ても文字列化して扱います。
- `matcher` フィールドに `"*"` 等を指定すると、動作確認した環境（codex-cli 0.149.1）では
  フック自体が発火しませんでした。`hooks/codex-hooks.json` では意図的に `matcher` を省略しています。
- `PreToolUse`/`PermissionRequest` はブロック判定を伴う可能性があるイベントのため `async` を付けていません。
  それ以外（`SessionStart`/`UserPromptSubmit`/`PostToolUse`/`Stop`/`SessionEnd`）は `async: true` にして
  本体の処理をブロックしないようにしています。

