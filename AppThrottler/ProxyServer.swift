import Foundation
import Network

// MARK: - Proxy Server (HTTP CONNECT + Throttle Relay)

@MainActor
class ProxyServer: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 9876
    @Published var connectedDevices: Int = 0
    @Published var throttledDevices: Set<String> = []  // device IPs with throttle active
    @Published var proxyError: String?
    @Published var trafficLog: [ProxyLogEntry] = []

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ProxyConnection] = [:]
    private var netService: NetService?

    struct ProxyLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let deviceIP: String
        let method: String
        let host: String
        let port: Int
        let isThrottled: Bool
    }

    struct DeviceInfo: Identifiable {
        let id: String  // IP address
        let name: String
        var isThrottled: Bool
        var connectionCount: Int
        var firstSeen: Date
    }

    var connectedDeviceList: [DeviceInfo] {
        var devices: [String: (count: Int, firstSeen: Date)] = [:]
        for (_, conn) in connections {
            let ip = conn.clientIP
            if let existing = devices[ip] {
                devices[ip] = (existing.count + 1, existing.firstSeen)
            } else {
                devices[ip] = (1, Date())
            }
        }
        return devices.map { ip, info in
            DeviceInfo(
                id: ip,
                name: deviceName(ip),
                isThrottled: throttledDevices.contains(ip),
                connectionCount: info.count,
                firstSeen: info.firstSeen
            )
        }.sorted { $0.firstSeen < $1.firstSeen }
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
                        self?.proxyError = nil
                        self?.publishBonjour()
                    case .failed(let err):
                        self?.isRunning = false
                        self?.proxyError = err.localizedDescription
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
            proxyError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, conn) in connections { conn.cancel() }
        connections.removeAll()
        unpublishBonjour()
        isRunning = false
        connectedDevices = 0
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ nwConn: NWConnection) {
        let id = ObjectIdentifier(nwConn)
        let conn = ProxyConnection(nwConn: nwConn)
        connections[id] = conn
        connectedDevices = connectedDeviceList.count

        conn.onClose = { [weak self] in
            Task { @MainActor [weak self] in
                self?.connections.removeValue(forKey: id)
                self?.connectedDevices = self?.connectedDeviceList.count ?? 0
            }
        }

        conn.onLog = { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.trafficLog.insert(entry, at: 0)
                if (self?.trafficLog.count ?? 0) > 500 {
                    self?.trafficLog.removeLast()
                }
            }
        }

        conn.isThrottled = { [weak self] ip in
            return self?.throttledDevices.contains(ip) ?? false
        }

        conn.start()
    }

    // MARK: - Throttle Control

    func throttleDevice(_ ip: String, downloadKbps: Int, uploadKbps: Int, latencyMs: Int = 0, packetLoss: Double = 0) {
        // Create dnctl pipes specific to this device IP
        let downPipe = 200 + (abs(ip.hashValue) % 800)
        let upPipe = downPipe + 1

        var cfg = "bw \(downloadKbps > 0 ? "\(downloadKbps)Kbit/s" : "1Gbit/s")"
        if latencyMs > 0 { cfg += " delay \(latencyMs)" }
        if packetLoss > 0 { cfg += " plr \(String(format: "%.4f", packetLoss))" }

        var cfgUp = "bw \(uploadKbps > 0 ? "\(uploadKbps)Kbit/s" : "1Gbit/s")"
        if latencyMs > 0 { cfgUp += " delay \(latencyMs)" }
        if packetLoss > 0 { cfgUp += " plr \(String(format: "%.4f", packetLoss))" }

        let script = """
        pfctl -a appthrottler/proxy -F rules 2>/dev/null || true
        dnctl pipe \(downPipe) config \(cfg)
        dnctl pipe \(upPipe) config \(cfgUp)
        echo 'pass in quick from \(ip) to any dnpipe \(downPipe)
        pass out quick from any to \(ip) dnpipe \(upPipe)' | pfctl -a appthrottler/proxy -f -
        """

        let result = runPrivileged(script, prompt: "AppThrottler: 限速设备 \(ip)")
        if result.success {
            throttledDevices.insert(ip)
        }
    }

    func unthrottleDevice(_ ip: String) {
        let script = "pfctl -a appthrottler/proxy -F rules 2>/dev/null || true"
        _ = runPrivileged(script, prompt: "AppThrottler: 解除设备 \(ip) 限速")
        throttledDevices.remove(ip)
    }

    func unthrottleAll() {
        let script = "pfctl -a appthrottler/proxy -F rules 2>/dev/null || true"
        _ = runPrivileged(script, prompt: "AppThrottler: 解除所有设备限速")
        throttledDevices.removeAll()
    }

    // MARK: - Helpers

    private func deviceName(_ ip: String) -> String {
        if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
            return "设备 \(ip.components(separatedBy: ".").last ?? ip)"
        }
        return ip
    }

    private func publishBonjour() {
        netService = NetService(
            domain: "local.",
            type: "_appthrottler-proxy._tcp.",
            name: "AppThrottler Proxy",
            port: Int32(port)
        )
        netService?.publish()
    }

    private func unpublishBonjour() {
        netService?.stop()
        netService = nil
    }

    func setupInstructions() -> String {
        let ip = localIPAddress()
        return """
        iPhone 设置步骤：
        1. 打开 设置 → WiFi
        2. 点击当前 WiFi 名称旁边的 ⓘ
        3. 滚动到底部 → 配置代理 → 手动
        4. 服务器: \(ip)
        5. 端口: \(port)
        6. 点击 存储
        """
    }

    func localIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            if name == "en0" || name == "en1" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                address = String(cString: hostname)
                if address.contains(":") == false { break }  // Prefer IPv4
            }
        }
        return address
    }

    private func runPrivileged(_ script: String, prompt: String) -> (success: Bool, error: String?) {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = """
        do shell script "\(escaped)" with administrator privileges with prompt "\(prompt)"
        """
        var error: NSDictionary?
        if let scriptObj = NSAppleScript(source: appleScript) {
            let _ = scriptObj.executeAndReturnError(&error)
            if let err = error {
                return (false, err[NSAppleScript.errorMessage] as? String ?? "denied")
            }
            return (true, nil)
        }
        return (false, "Cannot execute")
    }
}

// MARK: - Proxy Connection (HTTP CONNECT Handler)

class ProxyConnection {
    let nwConn: NWConnection
    var clientIP: String = "unknown"
    var onClose: (() -> Void)?
    var onLog: ((ProxyServer.ProxyLogEntry) -> Void)?
    var isThrottled: ((String) -> Bool) = { _ in false }

    private var targetConn: NWConnection?
    private var isCancelled = false

    init(nwConn: NWConnection) {
        self.nwConn = nwConn
        // Extract client IP
        if case .hostPort(let host, _) = nwConn.currentPath?.remoteEndpoint {
            clientIP = "\(host)"
        }
    }

    func start() {
        nwConn.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.cancel() }
            if case .cancelled = state { self?.onClose?() }
        }
        nwConn.start(queue: .global(qos: .userInitiated))
        receiveRequest()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        nwConn.cancel()
        targetConn?.cancel()
        onClose?()
    }

    // MARK: - HTTP CONNECT Proxy

    private func receiveRequest() {
        nwConn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                if isComplete || error != nil { self?.cancel() }
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            let lines = request.components(separatedBy: "\r\n")
            guard let firstLine = lines.first else { self.cancel(); return }

            let parts = firstLine.split(separator: " ").map(String.init)
            guard parts.count >= 3 else { self.cancel(); return }

            let method = parts[0].uppercased()

            if method == "CONNECT" {
                // HTTP CONNECT tunnel
                let hostPort = parts[1]
                let hostComponents = hostPort.split(separator: ":")
                let host = String(hostComponents[0])
                let port = Int(hostComponents.count > 1 ? hostComponents[1] : "443") ?? 443

                self.onLog?(ProxyServer.ProxyLogEntry(
                    timestamp: Date(), deviceIP: self.clientIP,
                    method: "CONNECT", host: host, port: port,
                    isThrottled: self.isThrottled(self.clientIP)
                ))

                self.handleConnect(host: host, port: port, originalData: data)
            } else {
                // Plain HTTP proxy
                guard let url = URL(string: parts[1]),
                      let host = url.host else { self.cancel(); return }
                let port = url.port ?? 80

                self.onLog?(ProxyServer.ProxyLogEntry(
                    timestamp: Date(), deviceIP: self.clientIP,
                    method: method, host: host, port: port,
                    isThrottled: self.isThrottled(self.clientIP)
                ))

                self.handleHTTP(host: host, port: port, requestData: data)
            }
        }
    }

    private func handleConnect(host: String, port: Int, originalData: Data) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        targetConn = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Send 200 OK back to client
                let response = "HTTP/1.1 200 Connection Established\r\n\r\n"
                self?.nwConn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
                // Start bidirectional relay
                self?.relay(self?.nwConn, to: conn)
                self?.relay(conn, to: self?.nwConn)
            case .failed:
                let response = "HTTP/1.1 502 Bad Gateway\r\n\r\n"
                self?.nwConn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    self?.cancel()
                })
            default: break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    private func handleHTTP(host: String, port: Int, requestData: Data) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        targetConn = conn

        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                // Forward the original request
                conn.send(content: requestData, completion: .contentProcessed { _ in })
                // Relay remaining data
                self?.relay(self?.nwConn, to: conn)
                self?.relay(conn, to: self?.nwConn)
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    // MARK: - Bidirectional Relay

    private func relay(_ from: NWConnection?, to: NWConnection?) {
        guard let from, let to else { return }
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self, !self.isCancelled else { return }
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { [weak self] _ in
                    self?.relay(from, to: to)
                })
            } else if isComplete {
                to.send(content: nil, completion: .contentProcessed { [weak self] _ in
                    self?.cancel()
                })
            } else {
                self.relay(from, to: to)
            }
        }
    }
}
