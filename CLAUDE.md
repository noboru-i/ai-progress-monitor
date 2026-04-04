# OTel AI Monitor

## プロジェクト概要

Claude Code および GitHub Copilot（VS Code）の OpenTelemetry データを受信し、  
「直近でAIが何をしているか・そこから何秒経過しているか」を  
**常に最前面に浮かぶ小さなウィンドウ**に表示し続けるMacアプリ。

---

## アーキテクチャ

```
Claude Code ──(OTLP/HTTP JSON, port 4318)──┐
                                            ├──→ OTLPReceiver（HTTP サーバー）
Copilot (VS Code) ─(OTLP/HTTP JSON, 4318)──┘         ↓
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
├── OTLPReceiver.swift        # HTTPサーバー・OTLPパーサー（Network.framework）
├── StatusStore.swift         # セッション状態管理（ObservableObject）
├── FloatingWindowView.swift  # 浮きウィンドウのSwiftUI View
├── MenuBarView.swift         # メニューバーPopover（全セッション詳細）
└── Models.swift              # SessionState / Source / Status 定義
```

---

## OTLPエクスポーター設定（利用者側の設定）

### Claude Code（~/.claude/settings.json）

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
    "OTEL_LOGS_EXPORT_INTERVAL": "2000",
    "OTEL_LOG_TOOL_DETAILS": "1"
  }
}
```

### GitHub Copilot（VS Code settings.json）

```json
{
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "otlp-http",
  "github.copilot.chat.otel.otlpEndpoint": "http://localhost:4318"
}
```

---

## テスト用ダミーデータ（curl）

```bash
# セッション1: tool_result
curl -v -X POST http://localhost:4318/v1/logs \
  -H "Content-Type: application/json" \
  -d '{
    "resourceLogs": [{
      "resource": {"attributes": [
        {"key": "service.name", "value": {"stringValue": "claude-code"}}
      ]},
      "scopeLogs": [{"logRecords": [{
        "timeUnixNano": "'$(date +%s)'000000000",
        "attributes": [
          {"key": "session.id",  "value": {"stringValue": "sess-aaa-1111"}},
          {"key": "event.name",  "value": {"stringValue": "claude_code.tool_result"}},
          {"key": "tool_name",   "value": {"stringValue": "Bash"}},
          {"key": "success",     "value": {"stringValue": "true"}},
          {"key": "tool_parameters", "value": {"stringValue": "{\"bash_command\":\"git diff HEAD\"}"}}
        ]
      }]}]
    }]
  }'

# セッション2: api_request（別ターミナル）
curl -v -X POST http://localhost:4318/v1/logs \
  -H "Content-Type: application/json" \
  -d '{
    "resourceLogs": [{
      "resource": {"attributes": [
        {"key": "service.name", "value": {"stringValue": "claude-code"}}
      ]},
      "scopeLogs": [{"logRecords": [{
        "timeUnixNano": "'$(date +%s)'000000000",
        "attributes": [
          {"key": "session.id",  "value": {"stringValue": "sess-bbb-2222"}},
          {"key": "event.name",  "value": {"stringValue": "claude_code.api_request"}},
          {"key": "model",       "value": {"stringValue": "claude-sonnet-4-6"}}
        ]
      }]}]
    }]
  }'
```

---

## 注意事項・制約

- **ローカル完結が前提**: OTLPデータにはBashコマンドや操作ファイルパスが含まれるため外部送信しないこと
- **Copilotの入力待ち検知**: Copilotに `Notification` Hook 相当イベントが現時点でないため、タイマー推定のみ
- **Copilotのスパン**: スパンは完了後に送信されるため「進行中」の正確な検知は難しく「最後のスパン受信からN秒経過」で表現する
- **Metricsエクスポート不要**: リアルタイム表示にはLogsのみで十分。`OTEL_METRICS_EXPORTER` は設定不要
- **session.id 欠落対策**: フォールバックキーで同一セッションのイベントを集約する（OTLPReceiver参照）
- **ウィンドウ操作**: `isMovableByWindowBackground = true` でドラッグ移動。`ignoresMouseEvents` は使わずクリックで拡張/縮小できるようにする
