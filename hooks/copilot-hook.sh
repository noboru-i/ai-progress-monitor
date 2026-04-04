#!/bin/bash
# AI Progress Monitor - VS Code Copilot hook script
# Reads hook event data from stdin and sends it to the macOS app via Unix socket.
#
# Setup: Copy hooks/copilot-hooks.json to one of:
#   - ~/.copilot/hooks/ai-progress-monitor.json  (グローバル)
#   - .github/hooks/ai-progress-monitor.json      (プロジェクト単位)
#
# スクリプト本体はアプリサポートディレクトリに配置してください:
#   cp hooks/copilot-hook.sh ~/Library/Application\ Support/AIProgressMonitor/copilot-hook.sh
#   chmod +x ~/Library/Application\ Support/AIProgressMonitor/copilot-hook.sh

SOCKET_PATH="$HOME/Library/Application Support/AIProgressMonitor/monitor.sock"

# アプリが起動していない場合は即終了
if [ ! -S "$SOCKET_PATH" ]; then
    echo '{"continue":true}'
    exit 0
fi

# stdin のフックデータを読み込み
export _HOOK_JSON="$(cat)"
# 第1引数からイベント名を受け取る（copilot-hooks.jsonで渡す）
export _HOOK_EVENT_NAME="${1:-}"

/usr/bin/python3 - <<'PYEOF'
import json, sys, os, socket, time, hashlib

try:
    hook_data = json.loads(os.environ.get("_HOOK_JSON", "{}"))
except Exception:
    hook_data = {}

sock_path = os.path.expanduser(
    os.environ.get("HOME", "~") + "/Library/Application Support/AIProgressMonitor/monitor.sock"
)

# hookEventName はペイロードにない場合があるため引数からフォールバック
event_name = hook_data.get("hookEventName") or os.environ.get("_HOOK_EVENT_NAME") or "unknown"
tool_name = hook_data.get("tool_name")
tool_input = hook_data.get("tool_input") or {}
# tool_detail: terminalはcommand、ファイル操作はfile_path
tool_detail = tool_input.get("command") or tool_input.get("file_path")

# Copilot固有イベントをアプリ内イベントにリマッピング
if event_name == "SubagentStart":
    event_name = "PreToolUse"
    tool_name = "Subagent"
elif event_name == "SubagentStop":
    event_name = "PostToolUse"
    tool_name = "Subagent"
elif event_name == "PreCompact":
    event_name = "PreToolUse"
    tool_name = "Compact"

# timestampの処理: ISO文字列またはepoch数値を受け付ける
ts = hook_data.get("timestamp")
if isinstance(ts, str):
    try:
        from datetime import datetime, timezone
        ts = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except Exception:
        ts = time.time()
elif not isinstance(ts, (int, float)):
    ts = time.time()

project_dir = hook_data.get("cwd") or os.getcwd()
# sessionId がない場合は cwd のハッシュから生成（Copilot固定セッションID）
raw_session_id = hook_data.get("sessionId")
if not raw_session_id:
    raw_session_id = "copilot-" + hashlib.md5(project_dir.encode()).hexdigest()[:8]

event = {
    "session_id": raw_session_id,
    "project_dir": project_dir,
    "event": event_name,
    "tool_name": tool_name,
    "tool_detail": tool_detail,
    "model": None,
    "notification_type": None,
    "timestamp": ts,
}

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    s.connect(sock_path)
    s.sendall(json.dumps(event).encode("utf-8"))
    s.close()
except Exception:
    pass  # アプリ未起動時などは無視

# Copilot hooks はstdoutにJSONを要求する
print(json.dumps({"continue": True}))
PYEOF

exit 0
