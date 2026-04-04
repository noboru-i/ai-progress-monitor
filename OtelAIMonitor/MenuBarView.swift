import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: StatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ExpandedView().environmentObject(store)
            Divider()
            HStack {
                Text("AI Progress Monitor").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.caption)
            }
        }
        .padding(10)
        .frame(minWidth: 300)
    }
}
