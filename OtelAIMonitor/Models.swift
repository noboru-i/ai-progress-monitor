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
