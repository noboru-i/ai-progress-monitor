import Foundation
import os.log

private let logger = Logger(subsystem: "com.noboru-i.AIProgressMonitor", category: "HookSocketServer")

struct HookEvent: Codable {
    let sessionId: String
    let projectDir: String
    let event: String
    let toolName: String?
    let toolDetail: String?
    let model: String?
    let notificationType: String?
    let timestamp: TimeInterval
    let source: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case projectDir = "project_dir"
        case event
        case toolName = "tool_name"
        case toolDetail = "tool_detail"
        case model
        case notificationType = "notification_type"
        case timestamp
        case source
    }
}

class HookSocketServer {
    var onEvent: ((HookEvent) -> Void)?
    private var serverFd: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.noboru-i.AIProgressMonitor.socket", attributes: .concurrent)

    static let socketDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AIProgressMonitor")
    static let socketPath = socketDir.appendingPathComponent("monitor.sock").path

    func start() throws {
        let dir = HookSocketServer.socketDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let path = HookSocketServer.socketPath
        unlink(path)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            throw NSError(domain: POSIXError.errorDomain, code: Int(errno))
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            path.withCString { src in
                let count = min(strlen(src) + 1, dst.count)
                dst.copyMemory(from: UnsafeRawBufferPointer(start: src, count: count))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFd)
            throw NSError(domain: POSIXError.errorDomain, code: Int(errno))
        }

        guard listen(serverFd, 10) == 0 else {
            close(serverFd)
            throw NSError(domain: POSIXError.errorDomain, code: Int(errno))
        }

        isRunning = true
        logger.info("Started at \(path, privacy: .public)")
        queue.async { self.acceptLoop() }
    }

    private func acceptLoop() {
        while isRunning {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else { break }
            queue.async { self.handleClient(clientFd) }
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[..<n])
        }
        guard !data.isEmpty,
              let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
            logger.warning("Failed to decode hook event")
            return
        }
        logger.info("event=\(event.event, privacy: .public) session=\(event.sessionId, privacy: .public) project=\(URL(fileURLWithPath: event.projectDir).lastPathComponent, privacy: .public)")
        onEvent?(event)
    }

    func stop() {
        isRunning = false
        close(serverFd)
        unlink(HookSocketServer.socketPath)
    }
}
