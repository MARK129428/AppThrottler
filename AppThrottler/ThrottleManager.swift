import Foundation
import AppKit

@MainActor
class ThrottleManager: ObservableObject {
    @Published var throttledPIDs: Set<Int32> = []
    @Published var showResultAlert = false
    @Published var resultMessage = ""
    @Published var logEntries: [LogEntry] = []

    private var pipeMapping: [Int32: PipeInfo] = [:]
    private var nextPipeNum: Int = 100
    private let anchorName = "appthrottler"

    struct PipeInfo {
        let downloadPipe: Int
        let uploadPipe: Int
        let config: ThrottleConfig
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let appName: String
        let action: String
        let detail: String

        static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f
        }()

        var timeString: String {
            Self.dateFormatter.string(from: timestamp)
        }
    }

    // MARK: - Status

    func isThrottled(pid: Int32) -> Bool {
        throttledPIDs.contains(pid)
    }

    func currentConfig(pid: Int32) -> ThrottleConfig? {
        pipeMapping[pid]?.config
    }

    func currentSettings(pid: Int32) -> (downloadKbps: Int, uploadKbps: Int)? {
        guard let info = pipeMapping[pid] else { return nil }
        return (info.config.downloadKbps, info.config.uploadKbps)
    }

    // MARK: - Apply Throttle

    func applyThrottle(app: AppProcess, config: ThrottleConfig) {
        guard !config.isUnlimited else {
            resultMessage = "请至少设置一项网络限制"
            showResultAlert = true
            return
        }

        let downPipe = nextPipeNum
        let upPipe = nextPipeNum + 1
        nextPipeNum += 2

        let connections = getProcessConnections(pid: app.pid)
        guard !connections.isEmpty else {
            resultMessage = "未找到 \(app.name) 的网络连接。\n应用可能没有活跃的网络活动，请先使用应用联网后再试。"
            showResultAlert = true
            return
        }

        // Remove existing pipes if re-applying
        if let old = pipeMapping[app.pid] {
            runShell("dnctl pipe \(old.downloadPipe) delete 2>/dev/null; dnctl pipe \(old.uploadPipe) delete 2>/dev/null")
        }

        var commands: [String] = []
        var pipeDescs: [String] = []

        // Build dnctl pipe config string
        func pipeConfig(kbps: Int) -> String {
            var parts: [String] = []
            if kbps > 0 { parts.append("bw \(kbps)Kbit/s") }
            if config.latencyMs > 0 { parts.append("delay \(config.latencyMs)") }
            if config.packetLoss > 0 { parts.append("plr \(String(format: "%.4f", config.packetLoss))") }
            if parts.isEmpty { parts.append("bw 1Gbit/s") } // delay/loss only
            return parts.joined(separator: " ")
        }

        let needsDownPipe = config.downloadKbps > 0 || config.latencyMs > 0 || config.packetLoss > 0
        let needsUpPipe = config.uploadKbps > 0 || config.latencyMs > 0 || config.packetLoss > 0

        if needsDownPipe {
            commands.append("dnctl pipe \(downPipe) config \(pipeConfig(kbps: config.downloadKbps))")
        }
        if needsUpPipe {
            let upKbps = config.uploadKbps > 0 ? config.uploadKbps : 0
            commands.append("dnctl pipe \(upPipe) config \(pipeConfig(kbps: upKbps))")
        }

        // Build PF rules
        var pfRules = ""
        for conn in connections {
            if needsDownPipe {
                pfRules += "pass in quick proto \(conn.proto) from any to any port \(conn.localPort) dnpipe \(downPipe)\n"
            }
            if needsUpPipe {
                pfRules += "pass out quick proto \(conn.proto) from any to any port \(conn.localPort) dnpipe \(upPipe)\n"
            }
        }

        let fullScript = """
        pfctl -a \(anchorName) -F rules 2>/dev/null || true
        \(commands.joined(separator: "\n"))
        (echo 'rdr-anchor "\(anchorName)"'; echo 'anchor "\(anchorName)"') | pfctl -f - 2>/dev/null
        echo '\(pfRules)' | pfctl -a \(anchorName) -f -
        """

        let result = runWithPrivileges(script: fullScript, prompt: "AppThrottler 需要管理员权限来限制 \(app.name)")

        if result.success {
            pipeMapping[app.pid] = PipeInfo(downloadPipe: downPipe, uploadPipe: upPipe, config: config)
            throttledPIDs.insert(app.pid)

            // Build description
            if config.downloadKbps > 0 { pipeDescs.append("↓\(formatSpeed(kbps: config.downloadKbps))") }
            if config.uploadKbps > 0 { pipeDescs.append("↑\(formatSpeed(kbps: config.uploadKbps))") }
            if config.latencyMs > 0 { pipeDescs.append("延迟\(config.latencyMs)ms") }
            if config.packetLoss > 0 { pipeDescs.append("丢包\(Int(config.packetLoss * 100))%") }

            resultMessage = "已对 \(app.name) 应用网络限制\n\(pipeDescs.joined(separator: " / "))"
            addLog(appName: app.name, action: "应用限速", detail: pipeDescs.joined(separator: ", "))
        } else {
            resultMessage = "限速失败: \(result.error ?? "未知错误")"
            addLog(appName: app.name, action: "限速失败", detail: result.error ?? "")
        }
        showResultAlert = true
    }

    func applyProfile(app: AppProcess, profile: NetworkProfile) {
        applyThrottle(app: app, config: profile.config)
    }

    // MARK: - Remove Throttle

    func removeThrottle(app: AppProcess) {
        guard let pipes = pipeMapping[app.pid] else { return }

        let script = """
        pfctl -a \(anchorName) -F rules 2>/dev/null || true
        dnctl pipe \(pipes.downloadPipe) delete 2>/dev/null || true
        dnctl pipe \(pipes.uploadPipe) delete 2>/dev/null || true
        """

        let result = runWithPrivileges(script: script, prompt: "AppThrottler 需要管理员权限来解除 \(app.name) 的限速")

        if result.success {
            pipeMapping.removeValue(forKey: app.pid)
            throttledPIDs.remove(app.pid)
            resultMessage = "已解除 \(app.name) 的限速"
            addLog(appName: app.name, action: "解除限速", detail: "")
        } else {
            resultMessage = "解除限速失败: \(result.error ?? "未知错误")"
        }
        showResultAlert = true
    }

    func removeAllThrottles() {
        guard !pipeMapping.isEmpty else { return }
        var commands: [String] = []
        for (_, pipes) in pipeMapping {
            commands.append("dnctl pipe \(pipes.downloadPipe) delete 2>/dev/null || true")
            commands.append("dnctl pipe \(pipes.uploadPipe) delete 2>/dev/null || true")
        }
        commands.append("pfctl -a \(anchorName) -F rules 2>/dev/null || true")

        _ = runWithPrivileges(
            script: commands.joined(separator: "\n"),
            prompt: "AppThrottler 需要管理员权限来清除所有限速"
        )
        let count = throttledPIDs.count
        pipeMapping.removeAll()
        throttledPIDs.removeAll()
        addLog(appName: "全部", action: "清除限速", detail: "共 \(count) 个应用")
    }

    // MARK: - Network Connection Discovery

    struct ConnectionInfo {
        let proto: String
        let localPort: String
        let remoteAddr: String?
        let remotePort: String
    }

    private func getProcessConnections(pid: Int32) -> [ConnectionInfo] {
        let result = exec("/usr/sbin/lsof", args: ["-i", "-n", "-P", "-p", "\(pid)"])
        guard let output = result else { return [] }

        var connections: [ConnectionInfo] = []
        var seen = Set<String>()

        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 9 else { continue }

            let proto = cols[7].lowercased()
            guard proto == "tcp" || proto == "udp" else { continue }

            let netField = cols[8]
            let parts = netField.components(separatedBy: "->")

            let localParts = parts[0].components(separatedBy: ":")
            let localPort = localParts.last ?? "*"

            var remoteAddr: String? = nil
            var remotePort = "*"

            if parts.count >= 2 {
                let remoteParts = parts[1].components(separatedBy: ":")
                remotePort = remoteParts.last ?? "*"
                if remoteParts.count >= 2 {
                    remoteAddr = remoteParts.dropLast().joined(separator: ":")
                }
            }

            let effectiveLocalPort = localPort == "*" ? nil : localPort
            let key = "\(proto):\(localPort):\(remoteAddr ?? "*"):\(remotePort)"
            guard seen.insert(key).inserted else { continue }

            if let lp = effectiveLocalPort {
                connections.append(ConnectionInfo(proto: proto, localPort: lp, remoteAddr: remoteAddr, remotePort: remotePort))
            }
        }

        return connections
    }

    // MARK: - Logging

    private func addLog(appName: String, action: String, detail: String) {
        let entry = LogEntry(timestamp: Date(), appName: appName, action: action, detail: detail)
        logEntries.insert(entry, at: 0)
        if logEntries.count > 200 { logEntries.removeLast() }
    }

    func clearLog() {
        logEntries.removeAll()
    }

    // MARK: - Helpers

    func formatSpeed(kbps: Int) -> String {
        if kbps >= 1000 {
            return String(format: "%.1f Mbps", Double(kbps) / 1000.0)
        }
        return "\(kbps) Kbps"
    }

    private func exec(_ path: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func runWithPrivileges(script: String, prompt: String) -> (success: Bool, error: String?) {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = """
        do shell script "\(escaped)" with administrator privileges with prompt "\(prompt)"
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            let _ = scriptObject.executeAndReturnError(&error)
            if let err = error {
                let msg = err[NSAppleScript.errorMessage] as? String ?? "权限被拒绝"
                return (false, msg)
            }
            return (true, nil)
        }
        return (false, "无法执行脚本")
    }

    private func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try? process.run()
        process.waitUntilExit()
    }
}
