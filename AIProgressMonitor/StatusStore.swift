import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.noboru-i.AIProgressMonitor", category: "StatusStore")

class StatusStore: ObservableObject {
    static let shared = StatusStore()

    @Published var sessions: [String: SessionState] = [:]

    private var cleanupTimer: Timer?

    private init() {
        startCleanupTimer()
    }

    func handleEvent(_ event: HookEvent) {
        let projectName = URL(fileURLWithPath: event.projectDir).lastPathComponent
        let eventTime = Date(timeIntervalSince1970: event.timestamp)
        let now = Date()
        let effectiveTime = eventTime > now ? now : eventTime

        logger.info("handleEvent: event=\(event.event) session=\(event.sessionId) project=\(projectName)")

        if var session = sessions[event.sessionId] {
            session.lastEventAt = effectiveTime
            session.projectName = projectName
            session.projectDir = event.projectDir
            applyEvent(event, to: &session)
            sessions[event.sessionId] = session
        } else {
            var session = SessionState(
                id: event.sessionId,
                projectName: projectName,
                projectDir: event.projectDir,
                status: .idle,
                toolName: nil,
                detail: nil,
                lastEventAt: effectiveTime,
                startedAt: now,
                model: nil
            )
            applyEvent(event, to: &session)
            sessions[event.sessionId] = session
        }

        enforceSessionLimit()
        logger.info("Session updated: \(event.sessionId) status=\(String(describing: self.sessions[event.sessionId]?.status))")
    }

    private func applyEvent(_ event: HookEvent, to session: inout SessionState) {
        switch event.event {
        case "UserPromptSubmit":
            session.status = .thinking

        case "PreToolUse":
            session.status = .toolRunning
            session.toolName = event.toolName
            session.detail = event.toolDetail

        case "PostToolUse":
            session.toolName = event.toolName
            session.detail = event.toolDetail
            // 次のPreToolUseかStopが来るまでtoolRunningのまま維持

        case "Notification":
            // matcher: idle_prompt で設定した場合のみここに到達
            session.status = .waitingInput

        case "Stop":
            session.status = .done

        case "SessionStart":
            session.status = .thinking
            if let model = event.model {
                session.model = model
            }

        case "SessionEnd":
            session.status = .done

        default:
            break
        }
    }

    private func enforceSessionLimit() {
        guard sessions.count > 20 else { return }
        let sorted = sessions.values.sorted { $0.lastEventAt < $1.lastEventAt }
        let toRemove = sorted.prefix(sessions.count - 20)
        for s in toRemove {
            sessions.removeValue(forKey: s.id)
        }
    }

    // MARK: - Computed Properties

    /// プロジェクト別グループ（コンパクト表示用）
    /// 各プロジェクトの代表セッション（最優先）と件数を返す
    var projectGroups: [(projectName: String, representative: SessionState, count: Int)] {
        let active = sessions.values.filter { $0.status != .idle }
        let grouped = Dictionary(grouping: active, by: \.projectName)
        return grouped.compactMap { (name, group) in
            guard let rep = group.min(by: { $0.status.priority < $1.status.priority }) else { return nil }
            return (projectName: name, representative: rep, count: group.count)
        }
        .sorted { $0.representative.status.priority < $1.representative.status.priority }
    }

    /// 全アクティブセッション（展開表示用）
    var activeSessions: [SessionState] {
        sessions.values
            .filter { $0.status != .idle }
            .sorted {
                if $0.projectName != $1.projectName { return $0.projectName < $1.projectName }
                return $0.status.priority < $1.status.priority
            }
    }

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
            }
        }

        if updated != sessions {
            sessions = updated
        }
    }
}
