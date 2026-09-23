import Foundation
import Network

// MARK: - API Models

struct APIProcessInfo: Codable {
    let pid: Int32
    let name: String
    let isThrottled: Bool
    let downloadKbps: Int
    let uploadKbps: Int
    let latencyMs: Int
    let packetLoss: Double
}

struct APIThrottleRequest: Codable {
    let pid: Int32
    let downloadKbps: Int?
    let uploadKbps: Int?
    let latencyMs: Int?
    let packetLoss: Double?
}

struct APIStatusResponse: Codable {
    let activeThrottles: Int
    let activeFaults: [String]
    let isCapturing: Bool
    let isMonitoring: Bool
}

struct APIGenericResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: - Server Manager

@MainActor
class ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 8427
    @Published var authToken: String = ""
    @Published var connectedClients = 0
    @Published var serverError: String?

    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private var wsConnections: [ObjectIdentifier: NWConnection] = [:]
    private var netService: NetService?

    private let tokenKey = "AppThrottler.ServerToken"

    init() {
        loadOrGenerateToken()
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.serverError = nil
                        self?.publishBonjour()
                    case .failed(let err):
                        self?.isRunning = false
                        self?.serverError = err.localizedDescription
                    default: break
                    }
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(conn)
                }
            }
            listener?.start(queue: .main)
        } catch {
            serverError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, conn) in activeConnections { conn.cancel() }
        for (_, conn) in wsConnections { conn.cancel() }
        activeConnections.removeAll()
        wsConnections.removeAll()
        unpublishBonjour()
        isRunning = false
        connectedClients = 0
    }

    func regenerateToken() {
        authToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).description
        UserDefaults.standard.set(authToken, forKey: tokenKey)
    }

    // MARK: - Connections

    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        activeConnections[id] = connection
        connectedClients = activeConnections.count + wsConnections.count

        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor [weak self] in
                    self?.activeConnections.removeValue(forKey: id)
                    self?.wsConnections.removeValue(forKey: id)
                    self?.connectedClients = (self?.activeConnections.count ?? 0) + (self?.wsConnections.count ?? 0)
                }
            }
        }

        connection.start(queue: .main)
        receiveRequest(connection: connection)
    }

    private func receiveRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, !data.isEmpty else {
                if isComplete || error != nil {
                    connection.cancel()
                }
                return
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                let response = self.processRequest(data: data, connection: connection)
                if let response {
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
        }
    }

    // MARK: - HTTP Processing

    private func processRequest(data: Data, connection: NWConnection) -> Data? {
        guard let request = String(data: data, encoding: .utf8) else { return nil }

        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        var path = parts[1]

        // Parse query string
        var queryParams: [String: String] = [:]
        if let qIdx = path.firstIndex(of: "?") {
            let queryStr = path[path.index(after: qIdx)...]
            path = String(path[path.startIndex..<qIdx])
            for pair in queryStr.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    queryParams[String(kv[0])] = String(kv[1])
                }
            }
        }

        // Parse headers
        var headers: [String: String] = [:]
        var bodyStart = false
        var bodyData = Data()
        for line in lines.dropFirst() {
            if bodyStart {
                if let d = line.data(using: .utf8) { bodyData.append(d) }
                continue
            }
            if line.isEmpty { bodyStart = true; continue }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        // Check for WebSocket upgrade
        if headers["upgrade"]?.lowercased() == "websocket" {
            handleWebSocketUpgrade(data: data, connection: connection, headers: headers)
            return nil // Don't close connection
        }

        // Auth check
        let token = headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        if path != "/health" && path != "/api/auth" && token != authToken {
            return httpResponse(status: 401, json: APIGenericResponse(success: false, message: "Unauthorized"))
        }

        // Route
        return route(method: method, path: path, body: bodyData, headers: headers)
    }

    // MARK: - Router

    private func route(method: String, path: String, body: Data, headers: [String: String]) -> Data {
        let pathComponents = path.split(separator: "/").map(String.init)

        switch (method, pathComponents) {
        // Health
        case ("GET", ["health"]):
            return jsonOK(["status": "ok", "version": "1.0.0"])

        // Auth
        case ("POST", ["api", "auth"]):
            guard let req = try? JSONDecoder().decode([String: String].self, from: body),
                  req["token"] == authToken else {
                return httpResponse(status: 401, json: APIGenericResponse(success: false, message: "Invalid token"))
            }
            return jsonOK(["success": true, "serverName": Host.current().localizedName ?? "Mac", "version": "1.0.0"] as [String: Any])

        // Processes
        case ("GET", ["api", "processes"]):
            return handleListProcesses()

        // Status
        case ("GET", ["api", "status"]):
            return handleGetStatus()

        // Apply throttle
        case ("POST", ["api", "throttle"]):
            return handleApplyThrottle(body: body)

        // Remove throttle by PID
        case ("DELETE", let path) where path.count == 3 && path[0] == "api" && path[1] == "throttle":
            if let pid = Int32(path[2]) {
                return handleRemoveThrottle(pid: pid)
            }
            return httpResponse(status: 400, json: APIGenericResponse(success: false, message: "Invalid PID"))

        // Remove all throttles
        case ("DELETE", ["api", "throttle"]):
            return handleRemoveAllThrottles()

        // Presets
        case ("GET", ["api", "presets"]):
            return handleListPresets()

        // Apply preset
        case ("POST", let path) where path.count == 3 && path[0] == "api" && path[1] == "preset":
            if let body = try? JSONDecoder().decode([String: Int32].self, from: body), let pid = body["pid"] {
                return handleApplyPreset(presetID: path[2], pid: pid)
            }
            return httpResponse(status: 400, json: APIGenericResponse(success: false, message: "Missing pid"))

        // Capture
        case ("POST", ["api", "capture", "start"]):
            return handleStartCapture(body: body)
        case ("POST", ["api", "capture", "stop"]):
            return handleStopCapture()

        // Traffic
        case ("GET", ["api", "traffic"]):
            return handleGetTraffic()
        case ("POST", ["api", "traffic", "start"]):
            return handleStartTraffic(body: body)
        case ("POST", ["api", "traffic", "stop"]):
            return handleStopTraffic()

        // Faults
        case ("GET", ["api", "faults"]):
            return handleListFaults()
        case ("POST", let path) where path.count == 3 && path[0] == "api" && path[1] == "fault":
            return handleToggleFault(type: path[2], body: body)
        case ("POST", ["api", "fault", "clear"]):
            return handleClearFaults()

        // Log
        case ("GET", ["api", "log"]):
            return handleGetLog()

        default:
            return httpResponse(status: 404, json: APIGenericResponse(success: false, message: "Not found"))
        }
    }

    // MARK: - Handlers

    // These would reference the actual managers injected from the app.
    // For now, stub implementations that return structure-correct responses.

    private func handleListProcesses() -> Data {
        // In production: processManager.apps.map { ... }
        return jsonOK(["processes": [] as [Any]])
    }

    private func handleGetStatus() -> Data {
        let resp = APIStatusResponse(activeThrottles: 0, activeFaults: [], isCapturing: false, isMonitoring: false)
        return jsonOK(resp)
    }

    private func handleApplyThrottle(body: Data) -> Data {
        guard let req = try? JSONDecoder().decode(APIThrottleRequest.self, from: body) else {
            return httpResponse(status: 400, json: APIGenericResponse(success: false, message: "Invalid request"))
        }
        // In production: throttleManager.applyThrottle(...)
        broadcastWS(type: "throttle.applied", data: ["pid": "\(req.pid)"])
        return jsonOK(APIGenericResponse(success: true, message: "Throttle applied to PID \(req.pid)"))
    }

    private func handleRemoveThrottle(pid: Int32) -> Data {
        // In production: throttleManager.removeThrottle(...)
        broadcastWS(type: "throttle.removed", data: ["pid": "\(pid)"])
        return jsonOK(APIGenericResponse(success: true, message: "Throttle removed from PID \(pid)"))
    }

    private func handleRemoveAllThrottles() -> Data {
        // In production: throttleManager.removeAllThrottles()
        broadcastWS(type: "throttle.cleared_all", data: [:])
        return jsonOK(APIGenericResponse(success: true, message: "All throttles removed"))
    }

    private func handleListPresets() -> Data {
        // In production: NetworkProfile.presets.map { ... }
        return jsonOK(["presets": [] as [Any]])
    }

    private func handleApplyPreset(presetID: String, pid: Int32) -> Data {
        guard NetworkProfile.presets.contains(where: { $0.id == presetID }) else {
            return httpResponse(status: 404, json: APIGenericResponse(success: false, message: "Preset not found"))
        }
        // In production: throttleManager.applyProfile(...)
        return jsonOK(APIGenericResponse(success: true, message: "Preset \(presetID) applied to PID \(pid)"))
    }

    private func handleStartCapture(body: Data) -> Data {
        guard let dict = try? JSONDecoder().decode([String: Int32].self, from: body), let pid = dict["pid"] else {
            return httpResponse(status: 400, json: APIGenericResponse(success: false, message: "Missing pid"))
        }
        // In production: packetCapture.startCapture(...)
        broadcastWS(type: "capture.started", data: ["pid": "\(pid)"])
        return jsonOK(APIGenericResponse(success: true, message: "Capture started for PID \(pid)"))
    }

    private func handleStopCapture() -> Data {
        // In production: packetCapture.stopCapture()
        broadcastWS(type: "capture.stopped", data: [:])
        return jsonOK(APIGenericResponse(success: true, message: "Capture stopped"))
    }

    private func handleGetTraffic() -> Data {
        // In production: trafficMonitor stats
        return jsonOK(["rateIn": 0, "rateOut": 0, "totalIn": 0, "totalOut": 0, "isMonitoring": false] as [String: Any])
    }

    private func handleStartTraffic(body: Data) -> Data {
        guard let dict = try? JSONDecoder().decode([String: Int32].self, from: body), let pid = dict["pid"] else {
            return httpResponse(status: 400, json: APIGenericResponse(success: false, message: "Missing pid"))
        }
        // In production: trafficMonitor.startMonitoring(pid:)
        return jsonOK(APIGenericResponse(success: true, message: "Traffic monitoring started for PID \(pid)"))
    }

    private func handleStopTraffic() -> Data {
        // In production: trafficMonitor.stopMonitoring()
        return jsonOK(APIGenericResponse(success: true, message: "Traffic monitoring stopped"))
    }

    private func handleListFaults() -> Data {
        let faults = FaultType.allCases.map { f in
            ["type": f.rawValue, "name": f.rawValue, "description": f.description, "active": false] as [String: Any]
        }
        return jsonOK(["faults": faults] as [String: Any])
    }

    private func handleToggleFault(type: String, body: Data) -> Data {
        guard FaultType.allCases.contains(where: { $0.rawValue == type }) else {
            return httpResponse(status: 404, json: APIGenericResponse(success: false, message: "Unknown fault type"))
        }
        // In production: faultInjector.toggle(fault:)
        broadcastWS(type: "fault.toggled", data: ["type": type])
        return jsonOK(APIGenericResponse(success: true, message: "Fault \(type) toggled"))
    }

    private func handleClearFaults() -> Data {
        // In production: faultInjector.deactivateAll()
        return jsonOK(APIGenericResponse(success: true, message: "All faults cleared"))
    }

    private func handleGetLog() -> Data {
        return jsonOK(["entries": [] as [Any]])
    }

    // MARK: - WebSocket

    private func handleWebSocketUpgrade(data: Data, connection: NWConnection, headers: [String: String]) {
        guard let key = headers["sec-websocket-key"] else {
            connection.cancel()
            return
        }

        // Generate accept key
        let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + guid
        let sha1 = combined.data(using: .utf8)!.sha1()
        let accept = sha1.base64EncodedString()

        let response = """
        HTTP/1.1 101 Switching Protocols\r\n\
        Upgrade: websocket\r\n\
        Connection: Upgrade\r\n\
        Sec-WebSocket-Accept: \(accept)\r\n\
        \r\n
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
        let id = ObjectIdentifier(connection)
        wsConnections[id] = connection
        connectedClients = activeConnections.count + wsConnections.count

        // Keep receiving to detect close
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, isComplete, _ in
            if isComplete {
                Task { @MainActor [weak self] in
                    self?.wsConnections.removeValue(forKey: id)
                    self?.connectedClients = (self?.activeConnections.count ?? 0) + (self?.wsConnections.count ?? 0)
                }
            }
        }
    }

    func broadcastWS(type: String, data: [String: String]) {
        let payload: [String: Any] = ["type": type, "data": data, "timestamp": Date().timeIntervalSince1970]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let frame = encodeWSTextFrame(String(data: jsonData, encoding: .utf8) ?? "{}")
        for (_, conn) in wsConnections {
            conn.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    private func encodeWSTextFrame(_ text: String) -> Data {
        guard let payload = text.data(using: .utf8) else { return Data() }
        var frame = Data()
        let length = payload.count

        // Opcode: 0x81 (FIN + text)
        frame.append(0x81)

        // Length (no mask, server→client)
        if length <= 125 {
            frame.append(UInt8(length))
        } else if length <= 65535 {
            frame.append(126)
            frame.append(UInt8(length >> 8))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            for i in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> i) & 0xFF))
            }
        }

        frame.append(payload)
        return frame
    }

    // MARK: - Bonjour

    private func publishBonjour() {
        netService = NetService(
            domain: "local.",
            type: "_appthrottler._tcp.",
            name: "AppThrottler-\(Host.current().localizedName ?? "Mac")",
            port: Int32(port)
        )
        netService?.setTXTRecord(NetService.data(fromTXTRecord: [
            "version": "1.0.0".data(using: .utf8)!,
            "name": (Host.current().localizedName ?? "Mac").data(using: .utf8)!
        ]))
        netService?.publish()
    }

    private func unpublishBonjour() {
        netService?.stop()
        netService = nil
    }

    // MARK: - Helpers

    private func loadOrGenerateToken() {
        if let saved = UserDefaults.standard.string(forKey: tokenKey), !saved.isEmpty {
            authToken = saved
        } else {
            regenerateToken()
        }
    }

    private func httpResponse(status: Int, json: some Codable) -> Data {
        let body = (try? JSONEncoder().encode(json)) ?? Data()
        let header = "HTTP/1.1 \(status) \(httpStatusText(status))\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = header.data(using: .utf8) ?? Data()
        data.append(body)
        return data
    }

    private func jsonOK(_ obj: some Codable) -> Data {
        httpResponse(status: 200, json: obj)
    }

    private func jsonOK(_ dict: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = header.data(using: .utf8) ?? Data()
        data.append(body)
        return data
    }

    private func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}

// MARK: - Data SHA1 Extension

extension Data {
    func sha1() -> Data {
        var digest = [UInt8](repeating: 0, count: 20)
        self.withUnsafeBytes { ptr in
            let bytes = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            CC_SHA1(bytes, CC_LONG(self.count), &digest)
        }
        return Data(digest)
    }
}

import CommonCrypto
