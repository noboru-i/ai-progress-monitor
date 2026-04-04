# AI Status Float — 実装指示書

## プロジェクト概要

Claude Code および GitHub Copilot（VS Code）の OpenTelemetry データを受信し、  
「直近でAIが何をしているか・そこから何秒経過しているか」を  
**常に最前面に浮かぶ小さなウィンドウ**に表示し続けるMacアプリを開発する。

Pipperのように、他のアプリを操作中でもウィンドウが隠れない。

### 完成イメージ

```
┌──────────────────────────────────── ✕ ┐  ← 半透明・角丸・常に最前面
│ 🧠 CC  Bash: git diff HEAD     12s   │
│ ⚙  CP  readFile: main.swift     3s   │
└───────────────────────────────────────┘
  ↑ ドラッグで任意の位置に移動可能
```

複数セッション時はウィンドウをクリックして拡張表示:

```
┌────────────────────────────────────── ✕ ┐
│ Claude Code                (3 sessions) │
│  [aaa1] ⚠  Bash: npm run dev    45s   │  ← 要注意を上に
│  [bbb2] 🧠  thinking...          8s   │
│  [ccc3] ✓   done                120s  │
│                                         │
│ Copilot                    (2 windows)  │
│  [ddd4] ⚙   readFile: main.swift  3s  │
│  [eee5] 🧠   thinking...          15s  │
└─────────────────────────────────────────┘
```

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
                                              ※ 常に最前面・半透明・ドラッグ可
```

### 設計方針

- **シングルターゲット**のMacアプリ（Widget Extension・App Groups・WidgetKit 不要）
- Apple Developer アカウント不要（証明書なしのローカル実行で十分）
- OTLPは `http/json` プロトコルのみサポート（実装シンプル化のため）
- ウィンドウは `NSWindow.level = .floating` で常に最前面に表示
- 経過秒は `TimelineView(.periodic)` で毎秒自動更新
- `session.id` 属性でセッション（ターミナル・ウィンドウ）ごとに状態を独立管理
- 外部プロセス（OTel Collector等）は不要。アプリ単体で完結

---

## 開発環境・前提条件

- macOS 13.0 (Ventura) 以上
- Xcode 15 以上
- Swift 5.9 以上
- Apple Developer アカウント **不要**（ローカル実行のみ）

---

## Xcodeプロジェクト構成

### ターゲット

| ターゲット名 | 種別 | 役割 |
|---|---|---|
| `AIStatusFloat` | macOS App | OTLPレシーバー + 浮きウィンドウ + メニューバーアイコン |

### ファイル構成

```
AIStatusFloat/
├── AIStatusFloatApp.swift    # エントリーポイント・NSWindowセットアップ
├── OTLPReceiver.swift        # HTTPサーバー・OTLPパーサー
├── StatusStore.swift         # セッション状態管理（ObservableObject）
├── FloatingWindowView.swift  # 浮きウィンドウのSwiftUI View
├── MenuBarView.swift         # メニューバーPopover（全セッション詳細）
└── Models.swift              # データモデル定義
```

---

## データモデル（Models.swift）

```swift
import Foundation
import SwiftUI

struct SessionState: Identifiable {
    var id: String           // OTelの session.id
    var source: Source
    var status: Status
    var toolName: String?
    var detail: String?      // Bashコマンド等（OTEL_LOG_TOOL_DETAILS=1 時）
    var lastEventAt: Date
    var startedAt: Date
    var model: String?

    enum Source: String {
        case claudeCode = "claude-code"
        case copilot    = "copilot-chat"

        var label: String {
            switch self {
            case .claudeCode: return "CC"
            case .copilot:    return "CP"
            }
        }
        var displayName: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .copilot:    return "Copilot"
            }
        }
    }

    enum Status {
        case idle
        case thinking     // api_request 受信後
        case toolRunning  // tool_result 受信後
        case waitingInput // 30秒以上無音 かつ 直前が thinking/toolRunning
        case done

        var icon: String {
            switch self {
            case .idle:         return "minus.circle"
            case .thinking:     return "brain"
            case .toolRunning:  return "gear"
            case .waitingInput: return "exclamationmark.circle"
            case .done:         return "checkmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .idle:         return .secondary
            case .thinking:     return .blue
            case .toolRunning:  return .green
            case .waitingInput: return .orange
            case .done:         return .gray
            }
        }

        /// 低いほど重要（コンパクト表示の代表選択・ソートに使用）
        var priority: Int {
            switch self {
            case .waitingInput: return 0
            case .toolRunning:  return 1
            case .thinking:     return 2
            case .done:         return 3
            case .idle:         return 4
            }
        }
    }

    var statusText: String {
        switch status {
        case .idle:         return "idle"
        case .thinking:     return model.map { "thinking... (\($0))" } ?? "thinking..."
        case .toolRunning:  return toolName ?? "running"
        case .waitingInput: return "⚠ 入力待ち"
        case .done:         return "done"
        }
    }

    /// セッションIDの短縮表示（末尾4文字）
    var shortId: String { String(id.suffix(4)) }
}
```

---

## OTLPレシーバー（OTLPReceiver.swift）

### 受信エンドポイント

| パス | 役割 |
|---|---|
| `POST /v1/logs` | Claude Code のイベント（tool_result, api_request 等）|
| `POST /v1/traces` | Copilot のスパン |
| `POST /v1/metrics` | 受け取るが無視する |

### 実装方針

`Network.framework` の `NWListener` でポート4318を待ち受ける。

```swift
class OTLPReceiver {
    var onEvent: ((OTLPEvent) -> Void)?

    func start(port: UInt16 = 4318) throws
    func stop()

    private func parseLogsBody(_ data: Data) -> [OTLPEvent]
    private func parseTracesBody(_ data: Data) -> [OTLPEvent]
}

struct OTLPEvent {
    let serviceName: String   // resource.attributes["service.name"]
    let sessionId: String     // 後述のフォールバックロジックで決定
    let eventName: String?    // attributes["event.name"]
    let toolName: String?     // attributes["tool_name"]
    let toolDetail: String?   // tool_parameters["bash_command"] 等
    let model: String?
    let timestamp: Date
}
```

### session.id のフォールバック

```
Claude Code (/v1/logs):
  logRecord.attributes["session.id"] を優先使用
  ない場合: resource.attributes["user.id"] + Unix時間/3600 でキーを生成

Copilot (/v1/traces):
  span.attributes["session.id"] を優先使用
  ない場合: resourceSpan の traceId をキーとして代用
```

### 主要な解析ロジック

```
/v1/logs:
  resourceLogs[].resource.attributes から service.name を取得
  logRecords[].attributes を走査:
    event.name = "claude_code.tool_result" → toolName, tool_parameters.bash_command を抽出
    event.name = "claude_code.api_request" → model を抽出
    event.name = "claude_code.user_prompt" → 状態リセット起点

/v1/traces:
  resourceSpans[].resource.attributes から service.name を取得
  spans[] を走査:
    name = "execute_tool" → toolRunning として toolName を抽出
    name = "chat"         → thinking として扱う
```

全エンドポイントに `HTTP 200 / Content-Type: application/json / Body: {}` を返す。

---

## 状態管理（StatusStore.swift）

```swift
class StatusStore: ObservableObject {
    static let shared = StatusStore()

    @Published var sessions: [String: SessionState] = [:]

    func handleEvent(_ event: OTLPEvent)

    var claudeSessions: [SessionState] {
        sessions.values
            .filter { $0.source == .claudeCode }
            .sorted { $0.status.priority < $1.status.priority }
    }

    var copilotSessions: [SessionState] {
        sessions.values
            .filter { $0.source == .copilot }
            .sorted { $0.status.priority < $1.status.priority }
    }

    /// 各ソースの代表（最優先）セッション
    var claudeRepresentative: SessionState? { claudeSessions.first }
    var copilotRepresentative: SessionState? { copilotSessions.first }

    /// waitingInput セッションが1つでもある
    var hasAlert: Bool {
        sessions.values.contains { $0.status == .waitingInput }
    }
}
```

### 状態遷移ルール

```
イベント受信時（event.sessionId でセッションを特定、なければ新規作成）:

  api_request 受信  → status = .thinking,    model を更新
  tool_result 受信  → status = .toolRunning, toolName, detail を更新
  user_prompt 受信  → status = .thinking（プロンプト処理開始）
```

### セッションクリーンアップ（5秒タイマー）

```
lastEventAt からの経過時間をチェック:

  30秒以上 かつ status が .thinking/.toolRunning → .waitingInput
  5分以上                                        → .idle
  10分以上                                       → sessions から削除

セッション上限: ソースあたり最大20件。超えたら lastEventAt が古いものから削除。
```

---

## 浮きウィンドウのセットアップ（AIStatusFloatApp.swift）

```swift
@main
struct AIStatusFloatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(appDelegate.store)
        } label: {
            // hasAlert のときアイコンをオレンジに変える
            Image(systemName: appDelegate.store.hasAlert
                  ? "exclamationmark.circle.fill"
                  : "cpu")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingWindow: NSWindow!
    let store    = StatusStore.shared
    let receiver = OTLPReceiver()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dockに表示しない
        NSApp.setActivationPolicy(.accessory)

        setupFloatingWindow()
        startReceiver()
    }

    private func setupFloatingWindow() {
        floatingWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 72),
            styleMask:   [.borderless, .resizable],
            backing:     .buffered,
            defer:       false
        )

        // ★ 常に最前面（他のアプリを操作中も隠れない）
        floatingWindow.level = .floating

        // 半透明・影
        floatingWindow.isOpaque        = false
        floatingWindow.backgroundColor = .clear
        floatingWindow.hasShadow       = true

        // Expose / Mission Control に出さない・全Spaceに表示
        floatingWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // タイトルバーなしでもドラッグで移動可能
        floatingWindow.isMovableByWindowBackground = true

        floatingWindow.contentView = NSHostingView(
            rootView: FloatingWindowView().environmentObject(store)
        )
        floatingWindow.makeKeyAndOrderFront(nil)
    }

    private func startReceiver() {
        receiver.onEvent = { [weak self] event in
            DispatchQueue.main.async { self?.store.handleEvent(event) }
        }
        try? receiver.start(port: 4318)
    }
}
```

---

## 浮きウィンドウのView（FloatingWindowView.swift）

- **コンパクトモード**（デフォルト）: 各ソースの代表セッション1行ずつ
- **拡張モード**（タップで切り替え）: 全セッションを個別表示

```swift
struct FloatingWindowView: View {
    @EnvironmentObject var store: StatusStore
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isExpanded {
                ExpandedView().environmentObject(store)
            } else {
                CompactView().environmentObject(store)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(radius: 4)
        )
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }
        .frame(minWidth: 280)
    }
}

// コンパクト: 各ソース1行
struct CompactView: View {
    @EnvironmentObject var store: StatusStore

    var body: some View {
        Group {
            if let cc = store.claudeRepresentative {
                SessionRow(session: cc, prefix: "CC",
                           badge: store.claudeSessions.count > 1 ? "×\(store.claudeSessions.count)" : nil)
            }
            if let cp = store.copilotRepresentative {
                SessionRow(session: cp, prefix: "CP",
                           badge: store.copilotSessions.count > 1 ? "×\(store.copilotSessions.count)" : nil)
            }
            if store.claudeRepresentative == nil && store.copilotRepresentative == nil {
                Text("idle").foregroundStyle(.secondary).font(.caption)
            }
        }
    }
}

// 拡張: 全セッション
struct ExpandedView: View {
    @EnvironmentObject var store: StatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.claudeSessions.isEmpty {
                Label("Claude Code", systemImage: "terminal").font(.caption2).foregroundStyle(.secondary)
                ForEach(store.claudeSessions) { s in
                    SessionRow(session: s, prefix: "[\(s.shortId)]", badge: nil)
                }
            }
            if !store.copilotSessions.isEmpty {
                Divider()
                Label("Copilot", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(store.copilotSessions) { s in
                    SessionRow(session: s, prefix: "[\(s.shortId)]", badge: nil)
                }
            }
        }
    }
}

// 1セッション1行
struct SessionRow: View {
    let session: SessionState
    let prefix: String
    let badge: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(prefix).font(.caption2.bold()).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
            if let badge { Text(badge).font(.caption2).foregroundStyle(.orange) }
            Image(systemName: session.status.icon).foregroundStyle(session.status.color).frame(width: 14)
            Text(session.statusText).font(.callout).lineLimit(1).truncationMode(.tail)
            Spacer()
            if session.status != .idle {
                ElapsedTimerView(since: session.lastEventAt)
            }
        }
    }
}

// 毎秒カウントアップ
struct ElapsedTimerView: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { ctx in
            let s = Int(ctx.date.timeIntervalSince(since))
            Text(s < 60 ? "\(s)s" : s < 3600 ? "\(s/60)m\(s%60)s" : "\(s/3600)h\(s%3600/60)m")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
```

---

## メニューバーPopover（MenuBarView.swift）

```swift
struct MenuBarView: View {
    @EnvironmentObject var store: StatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ExpandedView().environmentObject(store)
            Divider()
            HStack {
                Text("OTLP: localhost:4318").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("終了") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.caption)
            }
        }
        .padding(10)
        .frame(minWidth: 300)
    }
}
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

## 実装手順

### Step 1: Xcodeプロジェクト作成

1. macOS → App テンプレートで `AIStatusFloat` を作成
2. Info.plist に `Application is agent (UIElement)` = `YES`（`LSUIElement`）を追加
3. `NSApp.setActivationPolicy(.accessory)` でDockアイコンを非表示にする

### Step 2: Models.swift を実装

`SessionState` と各 enum を定義する。

### Step 3: OTLPReceiver.swift を実装

`Network.framework` の `NWListener` でポート4318を待ち受ける。  
`/v1/logs` と `/v1/traces` のJSONをパースし `OTLPEvent` に変換してcallbackで通知する。

### Step 4: StatusStore.swift を実装

イベントを受け取り `sessions` 辞書を更新する。5秒タイマーでクリーンアップを実行する。

### Step 5: FloatingWindowView.swift を実装

コンパクト・拡張の2モードと `ElapsedTimerView` を実装する。

### Step 6: AIStatusFloatApp.swift を実装

`NSWindow.level = .floating` の浮きウィンドウをセットアップし、OTLPReceiverを起動する。

### Step 7: MenuBarView.swift を実装

全セッション詳細と終了ボタンを実装する。

### Step 8: 結合テスト

1. アプリを起動し、浮きウィンドウが最前面に表示されることを確認
2. 別アプリ（Finder等）をクリックしてもウィンドウが隠れないことを確認
3. 以下の `curl` でウィンドウが更新されることを確認
4. 複数セッションのイベントを送り、コンパクト表示・拡張表示の切り替えを確認

---

## テスト用ダミーデータ（curl）

```bash
# セッション1: tool_result
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
          {"key": "success",     "value": {"stringValue": "true"}},
          {"key": "tool_parameters", "value": {"stringValue": "{\"bash_command\":\"git diff HEAD\"}"}}
        ]
      }]}]
    }]
  }'

# セッション2: api_request（別ターミナル）
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

## 注意事項・制約

- **ローカル完結が前提**: OTLPデータにはBashコマンドや操作ファイルパスが含まれるため外部送信しないこと
- **Copilotの入力待ち検知**: Copilotに `Notification` Hook 相当イベントが現時点でないため、タイマー推定のみ
- **Copilotのスパン**: スパンは完了後に送信されるため「進行中」の正確な検知は難しく「最後のスパン受信からN秒経過」で表現する
- **Metricsエクスポート不要**: リアルタイム表示にはLogsのみで十分。`OTEL_METRICS_EXPORTER` は設定不要
- **session.id 欠落対策**: フォールバックキーで同一セッションのイベントを集約する（OTLPReceiver参照）
- **セッション上限**: ソースあたり最大20件。超えたら `lastEventAt` が古いものから削除
- **ウィンドウ操作**: `isMovableByWindowBackground = true` でドラッグ移動を有効にする。`ignoresMouseEvents` は使わず、ウィンドウ自体はインタラクティブ（クリックで拡張/縮小）にする
