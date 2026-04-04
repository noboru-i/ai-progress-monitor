#!/bin/bash
# AI Progress Monitor - Claude Code hook script
# Reads hook event data from stdin and sends it to the macOS app via Unix socket.
#
# Setup in ~/.claude/settings.json:
#   {
#     "hooks": {
#       "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
#       "PreToolUse":       [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
#       "PostToolUse":      [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
#       "Notification":     [
#         {"matcher": "idle_prompt",       "hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]},
#         {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}
#       ],
#       "Stop":             [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
#       "SessionStart":     [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}],
#       "SessionEnd":       [{"hooks": [{"type": "command", "command": "/path/to/claude-code-hook.sh"}]}]
#     }
#   }

SOCKET_PATH="$HOME/Library/Application Support/AIProgressMonitor/monitor.sock"

# アプリが起動していない場合は即終了
[ -S "$SOCKET_PATH" ] || exit 0

# CLAUDE_PROJECT_DIR をエクスポート（Python側で参照）
export _PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# stdin のフックデータを読み込み（python3 - <<'PYEOF' だと heredoc が stdin を占有するため）
export _HOOK_JSON="$(cat)"

/usr/bin/python3 - <<'PYEOF'
import json, sys, os, socket, time

try:
    hook_data = json.loads(os.environ.get("_HOOK_JSON", "{}"))
except Exception:
    hook_data = {}

sock_path = os.path.expanduser(
    os.environ.get("HOME", "~") + "/Library/Application Support/AIProgressMonitor/monitor.sock"
)

tool_input = hook_data.get("tool_input") or {}
# tool_detail: Bashはcommand、Edit/Writeはfile_path
tool_detail = tool_input.get("command") or tool_input.get("file_path")

event = {
    "session_id": hook_data.get("session_id", "unknown"),
    "project_dir": os.environ.get("_PROJECT_DIR", os.getcwd()),
    "event": hook_data.get("hook_event_name", "unknown"),
    "tool_name": hook_data.get("tool_name"),
    "tool_detail": tool_detail,
    "model": hook_data.get("model"),
    "notification_type": hook_data.get("message"),
    "timestamp": time.time(),
}

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    s.connect(sock_path)
    s.sendall(json.dumps(event).encode("utf-8"))
    s.close()
except Exception:
    pass  # アプリ未起動時などは無視
PYEOF

exit 0
