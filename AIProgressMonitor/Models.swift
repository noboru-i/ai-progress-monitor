import Foundation
import SwiftUI

struct SessionState: Identifiable {
    var id: String           // session_id (from hook JSON)
    var projectName: String  // basename of projectDir
    var projectDir: String   // CLAUDE_PROJECT_DIR
    var status: Status
    var toolName: String?
    var detail: String?      // Bashコマンド等
    var lastEventAt: Date
    var startedAt: Date
    var model: String?

    enum Status {
        case idle
        case thinking
        case toolRunning
        case stalled            // toolRunning のまま一定時間経過（入力待ち疑い）
        case waitingInput       // Notification(idle_prompt) 受信時
        case permissionPrompt   // Notification(permission_prompt) 受信時
        case done

        var icon: String {
            switch self {
            case .idle:              return "minus.circle"
            case .thinking:          return "brain"
            case .toolRunning:       return "gear"
            case .stalled:           return "clock.badge.exclamationmark"
            case .waitingInput:      return "exclamationmark.circle.fill"
            case .permissionPrompt:  return "lock.circle.fill"
            case .done:              return "checkmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .idle:              return .gray
            case .thinking:          return .blue
            case .toolRunning:       return .blue
            case .stalled:           return .orange
            case .waitingInput:      return .orange
            case .permissionPrompt:  return .orange
            case .done:              return .gray
            }
        }

        /// 低いほど重要（コンパクト表示の代表選択・ソートに使用）
        var priority: Int {
            switch self {
            case .permissionPrompt: return 0
            case .waitingInput:     return 1
            case .stalled:          return 2
            case .toolRunning:      return 3
            case .thinking:         return 4
            case .done:             return 5
            case .idle:             return 6
            }
        }
    }

    var statusText: String {
        switch status {
        case .idle:              return "idle"
        case .thinking:          return model.map { "thinking... (\($0))" } ?? "thinking..."
        case .toolRunning:
            if let name = toolName, let d = detail, !d.isEmpty {
                let truncated = d.count > 40 ? String(d.prefix(40)) + "…" : d
                return "\(name): \(truncated)"
            }
            return toolName ?? "running"
        case .stalled:           return "stalled (no update)"
        case .waitingInput:      return "waiting for input"
        case .permissionPrompt:  return "permission required"
        case .done:              return "done"
        }
    }

    var shortId: String { String(id.suffix(4)) }
}

// MARK: - Equatable

extension SessionState: Equatable {
    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        lhs.id == rhs.id &&
        lhs.projectName == rhs.projectName &&
        lhs.status == rhs.status &&
        lhs.toolName == rhs.toolName &&
        lhs.detail == rhs.detail &&
        lhs.lastEventAt == rhs.lastEventAt &&
        lhs.model == rhs.model
    }
}

extension SessionState.Status: Equatable {}
