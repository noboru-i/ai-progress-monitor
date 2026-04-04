import Foundation
import Combine

class StatusStore: ObservableObject {
    static let shared = StatusStore()

    @Published var sessions: [String: SessionState] = [:]

    private var cleanupTimer: Timer?

    private init() {
        startCleanupTimer()
    }

    func handleEvent(_ event: OTLPEvent) {
        let source: SessionState.Source
        switch event.serviceName.lowercased() {
        case "claude-code", "claudecode":
            source = .claudeCode
        case "copilot-chat", "copilot", "github.copilot":
            source = .copilot
        default:
            // サービス名が一致しない場合はイベント名で判定
            if event.eventName?.hasPrefix("claude_code.") == true {
                source = .claudeCode
            } else {
                source = .copilot
            }
        }

        let now = Date()
        if var session = sessions[event.sessionId] {
            session.lastEventAt = event.timestamp > now ? now : event.timestamp
            applyEvent(event, to: &session)
            sessions[event.sessionId] = session
        } else {
            var session = SessionState(
                id: event.sessionId,
                source: source,
                status: .idle,
                toolName: nil,
                detail: nil,
                lastEventAt: event.timestamp > now ? now : event.timestamp,
                startedAt: now,
                model: nil
            )
            applyEvent(event, to: &session)
            sessions[event.sessionId] = session
        }

        enforceSessionLimit(for: source)
    }

    private func applyEvent(_ event: OTLPEvent, to session: inout SessionState) {
        switch event.eventName {
        case "claude_code.api_request":
            session.status = .thinking
            if let model = event.model {
                session.model = model
            }

        case "claude_code.tool_result":
            session.status = .toolRunning
            session.toolName = event.toolName
            session.detail = event.toolDetail

        case "claude_code.user_prompt":
            session.status = .thinking

        case "execute_tool":
            session.status = .toolRunning
            session.toolName = event.toolName

        case "chat":
            session.status = .thinking
            if let model = event.model {
                session.model = model
            }

        default:
            break
        }
    }

    private func enforceSessionLimit(for source: SessionState.Source) {
        let sourceSessions = sessions.values.filter { $0.source == source }
        if sourceSessions.count > 20 {
            let sorted = sourceSessions.sorted { $0.lastEventAt < $1.lastEventAt }
            let toRemove = sorted.prefix(sourceSessions.count - 20)
            for s in toRemove {
                sessions.removeValue(forKey: s.id)
            }
        }
    }

    // MARK: - Computed Properties

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

    var claudeRepresentative: SessionState? { claudeSessions.first }
    var copilotRepresentative: SessionState? { copilotSessions.first }

    var hasAlert: Bool {
        sessions.values.contains { $0.status == .waitingInput }
    }

    // MARK: - Cleanup Timer

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.runCleanup()
        }
    }

    private func runCleanup() {
        let now = Date()
        var updated = sessions

        for (key, var session) in updated {
            let elapsed = now.timeIntervalSince(session.lastEventAt)

            if elapsed >= 10 * 60 {
                // 10分以上 → 削除
                updated.removeValue(forKey: key)
            } else if elapsed >= 5 * 60 {
                // 5分以上 → idle
                session.status = .idle
                updated[key] = session
            } else if elapsed >= 30 && (session.status == .thinking || session.status == .toolRunning) {
                // 30秒以上 かつ thinking/toolRunning → waitingInput
                session.status = .waitingInput
                updated[key] = session
            }
        }

        if updated != sessions {
            sessions = updated
        }
    }
}

// 差分比較のために Equatable に準拠
extension SessionState: Equatable {
    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        lhs.id == rhs.id &&
        lhs.source == rhs.source &&
        lhs.status == rhs.status &&
        lhs.toolName == rhs.toolName &&
        lhs.detail == rhs.detail &&
        lhs.lastEventAt == rhs.lastEventAt &&
        lhs.model == rhs.model
    }
}

extension SessionState.Status: Equatable {}
