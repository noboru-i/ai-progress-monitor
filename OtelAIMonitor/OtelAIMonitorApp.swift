import SwiftUI
import AppKit

@main
struct OtelAIMonitorApp: App {
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

        // 常に最前面（他のアプリを操作中も隠れない）
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
