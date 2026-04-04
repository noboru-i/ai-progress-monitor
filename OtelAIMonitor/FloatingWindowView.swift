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
