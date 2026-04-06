import SwiftUI

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
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .colorScheme(.dark)
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }
        .frame(minWidth: 460)
    }
}

// コンパクト: セッションごとに1行
struct CompactView: View {
    @EnvironmentObject var store: StatusStore

    var body: some View {
        Group {
            if store.allSessions.isEmpty {
                Text("no sessions").foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(store.allSessions) { session in
                    SessionRow(
                        session: session,
                        prefix: session.projectName,
                        badge: nil
                    )
                }
            }
        }
    }
}

// 展開: 全セッションをプロジェクト別に表示
struct ExpandedView: View {
    @EnvironmentObject var store: StatusStore

    // プロジェクト名でグループ化（順序保持）
    private var grouped: [(projectName: String, sessions: [SessionState])] {
        var seen: [String] = []
        var result: [(String, [SessionState])] = []
        for s in store.activeSessions {
            if !seen.contains(s.projectName) {
                seen.append(s.projectName)
                result.append((s.projectName, []))
            }
            if let idx = result.firstIndex(where: { $0.0 == s.projectName }) {
                result[idx].1.append(s)
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if grouped.isEmpty {
                Text("idle").foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(grouped, id: \.projectName) { (name, sessions) in
                    Label(name, systemImage: "folder").font(.caption2).foregroundStyle(.secondary)
                    ForEach(sessions) { s in
                        SessionRow(session: s, prefix: "[\(s.shortId)]", badge: nil)
                            .padding(.leading, 8)
                    }
                    if grouped.last?.projectName != name {
                        Divider()
                    }
                }
            }
        }
    }
}

// 1セッション1行
struct SessionRow: View {
    @EnvironmentObject var store: StatusStore
    let session: SessionState
    let prefix: String
    let badge: String?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(prefix)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 100, alignment: .leading)

            if let badge {
                Text(badge).font(.caption2).foregroundStyle(.orange)
            }

            if session.status == .waitingInput || session.status == .permissionPrompt || session.status == .stalled {
                WaitingIndicator(color: session.status.color, icon: session.status.icon)
            } else {
                Image(systemName: session.status.icon)
                    .foregroundStyle(session.status.color)
                    .frame(width: 14)
            }

            Text(session.statusText)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if session.status != .idle {
                ElapsedTimerView(since: session.lastEventAt)
            }

            Button {
                store.removeSession(session.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(isHovered ? Color.white.opacity(0.8) : Color.clear)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
        .onHover { isHovered = $0 }
    }
}

// ユーザー対応が必要なパルスインジケーター
struct WaitingIndicator: View {
    let color: Color
    let icon: String
    @State private var pulse = false

    var body: some View {
        Image(systemName: icon)
            .foregroundStyle(color)
            .frame(width: 14)
            .scaleEffect(pulse ? 1.2 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
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
