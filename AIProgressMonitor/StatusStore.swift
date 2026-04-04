import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.noboru-i.AIProgressMonitor", category: "StatusStore")

class StatusStore: ObservableObject {
    static let shared = StatusStore()

    @Published var sessions: [String: SessionState] = [:]

    /// toolRunning のまま変化がなければ stalled に切り替える閾値（秒）
    static let stalledThreshold: TimeInterval = 30

    private var stalledTimer: Timer?

    private init() {
        stalledTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkStalledSessions()
        }
    }

    deinit {
        stalledTimer?.invalidate()
    }

    private func checkStalledSessions() {
        let now = Date()
        var changed = false
        for key in sessions.keys {
            if sessions[key]?.status == .toolRunning,
               let last = sessions[key]?.lastEventAt,
               now.timeIntervalSince(last) >= Self.stalledThreshold {
                sessions[key]?.status = .stalled
                changed = true
                NSSound.beep()
            }
        }
        if changed {
            logger.info("Marked stalled sessions")
        }
    }

    func handleEvent(_ event: HookEvent) {
        let projectName = URL(fileURLWithPath: event.projectDir).lastPathComponent
        let eventTime = Date(timeIntervalSince1970: event.timestamp)
        let now = Date()
        let effectiveTime = eventTime > now ? now : eventTime

        logger.info("handleEvent: event=\(event.event) session=\(event.sessionId) project=\(projectName)")

        if event.event == "SessionEnd" {
            sessions.removeValue(forKey: event.sessionId)
            enforceSessionLimit()
            return
        }

        if var session = sessions[event.sessionId] {
            session.lastEventAt = effectiveTime
            session.projectName = projectName
            session.projectDir = event.projectDir
            // stalled 中に新規イベントが来たら toolRunning に戻してから適用
            if session.status == .stalled { session.status = .toolRunning }
            let previousStatus = session.status
            applyEvent(event, to: &session)
            if shouldPlaySound(from: previousStatus, to: session.status) {
                NSSound.beep()
            }
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
            if shouldPlaySound(from: .idle, to: session.status) {
                NSSound.beep()
            }
            sessions[event.sessionId] = session
        }

        enforceSessionLimit()
        logger.info("Session updated: \(event.sessionId) status=\(String(describing: self.sessions[event.sessionId]?.status))")
    }

    private func isOrangeStatus(_ status: SessionState.Status) -> Bool {
        switch status {
        case .stalled, .waitingInput, .permissionPrompt: return true
        default: return false
        }
    }

    private func shouldPlaySound(from previous: SessionState.Status, to next: SessionState.Status) -> Bool {
        if !isOrangeStatus(previous) && isOrangeStatus(next) { return true }
        if previous != .done && next == .done { return true }
        return false
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
            if event.notificationType == "permission_prompt" {
                session.status = .permissionPrompt
            } else {
                // matcher: idle_prompt で設定した場合のみここに到達
                session.status = .waitingInput
            }

        case "Stop":
            session.status = .done

        case "SessionStart":
            session.status = .idle
            if let model = event.model {
                session.model = model
            }

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

    /// 全セッション（idle含む）
    var allSessions: [SessionState] {
        sessions.values
            .sorted {
                if $0.projectName != $1.projectName { return $0.projectName < $1.projectName }
                return $0.status.priority < $1.status.priority
            }
    }

    var hasAlert: Bool {
        sessions.values.contains { $0.status == .waitingInput || $0.status == .permissionPrompt }
    }

}
