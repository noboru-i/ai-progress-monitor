import Foundation
import Network

struct OTLPEvent {
    let serviceName: String   // resource.attributes["service.name"]
    let sessionId: String     // フォールバックロジックで決定
    let eventName: String?    // attributes["event.name"]
    let toolName: String?     // attributes["tool_name"]
    let toolDetail: String?   // tool_parameters["bash_command"] 等
    let model: String?
    let timestamp: Date
}

class OTLPReceiver {
    var onEvent: ((OTLPEvent) -> Void)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "otlp.receiver")

    func start(port: UInt16 = 4318) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection, buffer: Data())
    }

    private func receiveHTTPRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var accumulated = buffer
            if let data = data {
                accumulated.append(data)
            }
            // HTTPリクエストをパース
            if let request = self.parseHTTPRequest(accumulated) {
                self.handleHTTPRequest(request, connection: connection)
            } else if !isComplete && error == nil {
                self.receiveHTTPRequest(connection: connection, buffer: accumulated)
            } else {
                connection.cancel()
            }
        }
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let parts = str.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else { return nil }

        let headerSection = parts[0]
        let headerLines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else { return nil }
        let requestParts = requestLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        let method = requestParts[0]
        let path = requestParts[1]

        // Content-Length を取得してボディを抽出
        var contentLength = 0
        for line in headerLines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        let headerEndRange = str.range(of: "\r\n\r\n")!
        let headerEndIndex = data.distance(from: data.startIndex, to: data.index(data.startIndex, offsetBy: str.distance(from: str.startIndex, to: headerEndRange.upperBound)))

        let bodyData = data.dropFirst(headerEndIndex)
        if bodyData.count < contentLength {
            return nil // まだボディが揃っていない
        }

        let body = Data(bodyData.prefix(contentLength))
        return HTTPRequest(method: method, path: path, body: body)
    }

    private func handleHTTPRequest(_ request: HTTPRequest, connection: NWConnection) {
        var events: [OTLPEvent] = []

        if request.method == "POST" {
            switch request.path {
            case "/v1/logs":
                events = parseLogsBody(request.body)
            case "/v1/traces":
                events = parseTracesBody(request.body)
            default:
                break
            }
        }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        for event in events {
            onEvent?(event)
        }
    }

    // MARK: - JSON パーサーヘルパー

    private func stringValue(_ dict: [String: Any], key: String) -> String? {
        if let v = dict[key] as? [String: Any] {
            return v["stringValue"] as? String
        }
        return dict[key] as? String
    }

    private func attributeMap(_ attributes: [[String: Any]]) -> [String: String] {
        var result: [String: String] = [:]
        for attr in attributes {
            guard let key = attr["key"] as? String else { continue }
            if let valueDict = attr["value"] as? [String: Any] {
                if let sv = valueDict["stringValue"] as? String {
                    result[key] = sv
                } else if let iv = valueDict["intValue"] {
                    result[key] = "\(iv)"
                } else if let bv = valueDict["boolValue"] {
                    result[key] = "\(bv)"
                }
            }
        }
        return result
    }

    // MARK: - /v1/logs パース

    private func parseLogsBody(_ data: Data) -> [OTLPEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resourceLogs = json["resourceLogs"] as? [[String: Any]] else { return [] }

        var events: [OTLPEvent] = []

        for resourceLog in resourceLogs {
            let resourceAttrs = (resourceLog["resource"] as? [String: Any]).flatMap {
                $0["attributes"] as? [[String: Any]]
            } ?? []
            let resourceMap = attributeMap(resourceAttrs)
            let serviceName = resourceMap["service.name"] ?? "unknown"
            let userId = resourceMap["user.id"]

            let scopeLogs = resourceLog["scopeLogs"] as? [[String: Any]] ?? []
            for scopeLog in scopeLogs {
                let logRecords = scopeLog["logRecords"] as? [[String: Any]] ?? []
                for record in logRecords {
                    let attrs = record["attributes"] as? [[String: Any]] ?? []
                    let attrMap = attributeMap(attrs)

                    // session.id のフォールバック
                    let sessionId: String
                    if let sid = attrMap["session.id"] {
                        sessionId = sid
                    } else if let uid = userId {
                        let hour = Int(Date().timeIntervalSince1970) / 3600
                        sessionId = "\(uid)-\(hour)"
                    } else {
                        sessionId = "unknown-\(Int(Date().timeIntervalSince1970) / 3600)"
                    }

                    let eventName = attrMap["event.name"]
                    let toolName = attrMap["tool_name"]
                    let model = attrMap["model"]

                    // tool_parameters から bash_command を抽出
                    var toolDetail: String? = nil
                    if let toolParamsStr = attrMap["tool_parameters"],
                       let toolParamsData = toolParamsStr.data(using: .utf8),
                       let toolParams = try? JSONSerialization.jsonObject(with: toolParamsData) as? [String: Any] {
                        toolDetail = toolParams["bash_command"] as? String
                            ?? toolParams["file_path"] as? String
                    }

                    let timestamp: Date
                    if let timeNanoStr = record["timeUnixNano"] as? String,
                       let timeNano = Double(timeNanoStr) {
                        timestamp = Date(timeIntervalSince1970: timeNano / 1_000_000_000)
                    } else {
                        timestamp = Date()
                    }

                    let event = OTLPEvent(
                        serviceName: serviceName,
                        sessionId: sessionId,
                        eventName: eventName,
                        toolName: toolName,
                        toolDetail: toolDetail,
                        model: model,
                        timestamp: timestamp
                    )
                    events.append(event)
                }
            }
        }

        return events
    }

    // MARK: - /v1/traces パース

    private func parseTracesBody(_ data: Data) -> [OTLPEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resourceSpans = json["resourceSpans"] as? [[String: Any]] else { return [] }

        var events: [OTLPEvent] = []

        for resourceSpan in resourceSpans {
            let resourceAttrs = (resourceSpan["resource"] as? [String: Any]).flatMap {
                $0["attributes"] as? [[String: Any]]
            } ?? []
            let resourceMap = attributeMap(resourceAttrs)
            let serviceName = resourceMap["service.name"] ?? "unknown"

            let scopeSpans = resourceSpan["scopeSpans"] as? [[String: Any]] ?? []
            for scopeSpan in scopeSpans {
                let spans = scopeSpan["spans"] as? [[String: Any]] ?? []
                for span in spans {
                    let attrs = span["attributes"] as? [[String: Any]] ?? []
                    let attrMap = attributeMap(attrs)

                    // session.id のフォールバック
                    let sessionId: String
                    if let sid = attrMap["session.id"] {
                        sessionId = sid
                    } else if let traceId = span["traceId"] as? String {
                        sessionId = traceId
                    } else {
                        sessionId = "copilot-\(Int(Date().timeIntervalSince1970) / 3600)"
                    }

                    let spanName = span["name"] as? String ?? ""
                    let eventName: String?
                    let toolName: String?

                    switch spanName {
                    case "execute_tool":
                        eventName = "execute_tool"
                        toolName = attrMap["tool_name"] ?? attrMap["name"]
                    case "chat":
                        eventName = "chat"
                        toolName = nil
                    default:
                        eventName = spanName.isEmpty ? nil : spanName
                        toolName = nil
                    }

                    let timestamp: Date
                    if let timeNanoStr = span["startTimeUnixNano"] as? String,
                       let timeNano = Double(timeNanoStr) {
                        timestamp = Date(timeIntervalSince1970: timeNano / 1_000_000_000)
                    } else {
                        timestamp = Date()
                    }

                    let event = OTLPEvent(
                        serviceName: serviceName,
                        sessionId: sessionId,
                        eventName: eventName,
                        toolName: toolName,
                        toolDetail: nil,
                        model: attrMap["model"],
                        timestamp: timestamp
                    )
                    events.append(event)
                }
            }
        }

        return events
    }
}
