import SwiftUI
import AppKit

@main
struct AIProgressMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(appDelegate.store)
        } label: {
            Image(systemName: appDelegate.store.hasAlert
                  ? "exclamationmark.circle.fill"
                  : "cpu")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingWindow: NSWindow!
    let store = StatusStore.shared
    let socketServer = HookSocketServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupFloatingWindow()
        startSocketServer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer.stop()
    }

    private func setupFloatingWindow() {
        floatingWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 72),
            styleMask:   [.borderless, .resizable],
            backing:     .buffered,
            defer:       false
        )

        floatingWindow.level = .floating
        floatingWindow.isOpaque        = false
        floatingWindow.backgroundColor = .clear
        floatingWindow.hasShadow       = true
        floatingWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        floatingWindow.isMovableByWindowBackground = true

        floatingWindow.contentView = NSHostingView(
            rootView: FloatingWindowView().environmentObject(store)
        )
        floatingWindow.makeKeyAndOrderFront(nil)
    }

    private func startSocketServer() {
        socketServer.onEvent = { [weak self] event in
            DispatchQueue.main.async { self?.store.handleEvent(event) }
        }
        do {
            try socketServer.start()
        } catch {
            print("Failed to start socket server: \(error)")
        }
    }
}
