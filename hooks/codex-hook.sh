#!/bin/bash
# AI Progress Monitor - Codex CLI hook script
# Reads hook event data from stdin and sends it to the macOS app via Unix socket.
#
# Setup: Copy hooks/codex-hooks.json to one of:
#   - ~/.codex/hooks.json                    (グローバル)
#   - <repo>/.codex/hooks.json                (プロジェクト単位)
# もしくは同内容を ~/.codex/config.toml の [hooks] テーブルに埋め込んでください。
#
# スクリプト本体はアプリサポートディレクトリに配置してください:
#   cp hooks/codex-hook.sh ~/Library/Application\ Support/AIProgressMonitor/codex-hook.sh
#   chmod +x ~/Library/Application\ Support/AIProgressMonitor/codex-hook.sh
#
# Codex hooks は stdin から JSON を受け取り、stdout に {"continue": true} 等の
# JSON を返すことを期待する（Claude Code と異なり必須）。

SOCKET_PATH="$HOME/Library/Application Support/AIProgressMonitor/monitor.sock"

# アプリが起動していない場合は即終了
if [ ! -S "$SOCKET_PATH" ]; then
    echo '{"continue":true}'
    exit 0
fi

# stdin のフックデータを読み込み
export _HOOK_JSON="$(cat)"
# 第1引数からイベント名を受け取る（copilot-hooks.json同様、codex-hooks.jsonで渡す）
export _HOOK_EVENT_NAME="${1:-}"

/usr/bin/python3 - <<'PYEOF'
import json, sys, os, socket, time

try:
    hook_data = json.loads(os.environ.get("_HOOK_JSON", "{}"))
except Exception:
    hook_data = {}

sock_path = os.path.expanduser(
    os.environ.get("HOME", "~") + "/Library/Application Support/AIProgressMonitor/monitor.sock"
)


def as_str(value):
    """配列や数値が来ても安全に文字列へ正規化する（型不一致によるデコード失敗を防ぐ）"""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return " ".join(str(v) for v in value)
    return str(value)


# hook_event_name はペイロードにない場合があるため引数からフォールバック
event_name = hook_data.get("hook_event_name") or os.environ.get("_HOOK_EVENT_NAME") or "unknown"
tool_name = as_str(hook_data.get("tool_name"))
tool_input = hook_data.get("tool_input") or {}
# tool_detail: シェル実行系はcommand、ファイル操作はfile_path/path
raw_detail = tool_input.get("command") or tool_input.get("file_path") or tool_input.get("path")
tool_detail = as_str(raw_detail)

# session_id は Copilot と衝突しないよう codex- を付与
raw_session_id = hook_data.get("session_id") or "unknown"
session_id = f"codex-{raw_session_id}"

event = {
    "session_id": session_id,
    "project_dir": hook_data.get("cwd") or os.getcwd(),
    "event": event_name,
    "tool_name": tool_name,
    "tool_detail": tool_detail,
    "model": as_str(hook_data.get("model")),
    "notification_type": None,
    "timestamp": time.time(),
    "source": "codex",
}

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    s.connect(sock_path)
    s.sendall(json.dumps(event).encode("utf-8"))
    s.close()
except Exception:
    pass  # アプリ未起動時などは無視

# Codex hooks はstdoutにJSONを要求する
print(json.dumps({"continue": True}))
PYEOF

exit 0
