# セットアップガイド

OTel AI Monitor にテレメトリデータを送信するための設定手順です。

---

## Claude Code

プロジェクトルートの `.claude/settings.local.json` に設定済みです（このリポジトリをクローンすれば自動で適用されます）。

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

> **Note:** `.claude/settings.local.json` は `.gitignore` によりコミット対象外です。
> 全プロジェクト共通で有効にしたい場合は `~/.claude/settings.json` に同じ設定を追加してください。

| 環境変数 | 説明 |
|---|---|
| `CLAUDE_CODE_ENABLE_TELEMETRY` | テレメトリ送信を有効化 |
| `OTEL_LOGS_EXPORTER` | ログエクスポーターを OTLP に指定 |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | プロトコルを HTTP/JSON に指定 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | 送信先エンドポイント（OTel AI Monitor が待ち受けるアドレス） |
| `OTEL_LOGS_EXPORT_INTERVAL` | ログのエクスポート間隔（ミリ秒） |
| `OTEL_LOG_TOOL_DETAILS` | ツール実行のコマンド詳細を含める |

設定後、Claude Code を再起動すると反映されます。

---

## GitHub Copilot（VS Code）

VS Code の `settings.json`（`Cmd+Shift+P` → "Open User Settings (JSON)"）に以下を追加します。

```json
{
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "otlp-http",
  "github.copilot.chat.otel.otlpEndpoint": "http://localhost:4318"
}
```

| 設定キー | 説明 |
|---|---|
| `github.copilot.chat.otel.enabled` | Copilot の OTEL エクスポートを有効化 |
| `github.copilot.chat.otel.exporterType` | エクスポーター種別を OTLP HTTP に指定 |
| `github.copilot.chat.otel.otlpEndpoint` | 送信先エンドポイント |

設定後、VS Code を再起動すると反映されます。

---

## 動作確認

OTel AI Monitor を起動した状態で以下の `curl` コマンドを実行し、浮きウィンドウが更新されることを確認してください。

```bash
# Claude Code イベント（tool_result）のテスト
curl -s -X POST http://localhost:4318/v1/logs \
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
          {"key": "tool_parameters", "value": {"stringValue": "{\"bash_command\":\"git diff HEAD\"}"}}
        ]
      }]}]
    }]
  }'

# Claude Code イベント（api_request）のテスト
curl -s -X POST http://localhost:4318/v1/logs \
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

## 注意事項

- OTel AI Monitor はポート **4318** で待ち受けます。他のプロセスがポートを使用していないことを確認してください。
- OTLP データにはBashコマンドや操作ファイルパスが含まれるため、送信先は必ずローカルホストにしてください。
