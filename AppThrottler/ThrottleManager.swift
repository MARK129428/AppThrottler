import Foundation
import AppKit

// MARK: - Privileged Executor (background, non-blocking)

actor PrivilegedExecutor {
    static let shared = PrivilegedExecutor()

    func run(_ script: String, prompt: String) async -> (success: Bool, error: String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let escaped = script
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let appleScript = """
                do shell script "\(escaped)" with administrator privileges with prompt "\(prompt)"
                """
                var error: NSDictionary?
                if let scriptObj = NSAppleScript(source: appleScript) {
                    let _ = scriptObj.executeAndReturnError(&error)
                    if let err = error {
                        let msg = err[NSAppleScript.errorMessage] as? String ?? "denied"
                        continuation.resume(returning: (false, msg))
                    } else {
                        continuation.resume(returning: (true, nil))
                    }
                } else {
                    continuation.resume(returning: (false, "Cannot create script"))
                }
            }
        }
    }

    func runShell(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}

// MARK: - Throttle Manager (UID-based matching)

@MainActor
class ThrottleManager: ObservableObject {
    @Published var throttledPIDs: Set<Int32> = []
    @Published var showResultAlert = false
    @Published var resultMessage = ""
    @Published var logEntries: [LogEntry] = []
    @Published var isApplying = false  // UI can show spinner

    private var pipeMapping: [Int32: PipeInfo] = [:]
    private var nextPipeNum: Int = 100  // Range 100-499
    private let maxPipeNum = 499
    private let anchorName = "appthrottler"
    private let executor = PrivilegedExecutor.shared

    struct PipeInfo {
        let downloadPipe: Int
        let uploadPipe: Int
        let config: ThrottleConfig
        let uid: uid_t
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let appName: String
        let action: String
        let detail: String

        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: timestamp)
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

    // MARK: - Apply Throttle (async, non-blocking)

    func applyThrottle(app: AppProcess, config: ThrottleConfig) async {
        guard !config.isUnlimited else {
            resultMessage = "请至少设置一项网络限制"
            showResultAlert = true
            return
        }

        isApplying = true
        defer { isApplying = false }

        // Get the app's UID for stable PF matching
        let uid = await getUID(pid: app.pid)
        guard uid > 0 else {
            resultMessage = "无法获取 \(app.name) 的用户 ID"
            showResultAlert = true
            return
        }

        // Allocate pipe numbers (avoid collision with ProxyServer 500-899)
        let downPipe = allocatePipeNum()
        let upPipe = allocatePipeNum()

        // Remove old pipes if re-applying
        if let old = pipeMapping[app.pid] {
            await executor.runShell("dnctl pipe \(old.downloadPipe) delete 2>/dev/null; dnctl pipe \(old.uploadPipe) delete 2>/dev/null")
        }

        // Build dnctl pipe config
        func pipeConfig(kbps: Int) -> String {
            var parts: [String] = []
            if kbps > 0 { parts.append("bw \(kbps)Kbit/s") }
            if config.latencyMs > 0 { parts.append("delay \(config.latencyMs)") }
            if config.packetLoss > 0 { parts.append("plr \(String(format: "%.4f", config.packetLoss))") }
            if parts.isEmpty { parts.append("bw 1Gbit/s") }
            return parts.joined(separator: " ")
        }

        let needsDown = config.downloadKbps > 0 || config.latencyMs > 0 || config.packetLoss > 0
        let needsUp = config.uploadKbps > 0 || config.latencyMs > 0 || config.packetLoss > 0

        // Build script — uses UID-based rules instead of port-based
        var commands: [String] = []
        if needsDown {
            commands.append("dnctl pipe \(downPipe) config \(pipeConfig(kbps: config.downloadKbps))")
        }
        if needsUp {
            commands.append("dnctl pipe \(upPipe) config \(pipeConfig(kbps: config.uploadKbps > 0 ? config.uploadKbps : 0))")
        }

        var pfRules = ""
        if needsDown {
            pfRules += "pass in quick from any to user \(uid) dnpipe \(downPipe)\n"
        }
        if needsUp {
            pfRules += "pass out quick from user \(uid) to any dnpipe \(upPipe)\n"
        }

        // Preserve existing rules for other PIDs by reading current anchor
        let fullScript = """
        # Flush and rebuild anchor (preserves sub-anchors)
        pfctl -a \(anchorName) -F rules 2>/dev/null || true
        \(commands.joined(separator: "\n"))
        (echo 'rdr-anchor "\(anchorName)"'; echo 'anchor "\(anchorName)"') | pfctl -f - 2>/dev/null
        echo '\(pfRules)' | pfctl -a \(anchorName) -f -
        """

        let result = await executor.run(fullScript, prompt: "AppThrottler: 限制 \(app.name)")

        if result.success {
            pipeMapping[app.pid] = PipeInfo(downloadPipe: downPipe, uploadPipe: upPipe, config: config, uid: uid)
            throttledPIDs.insert(app.pid)

            var desc: [String] = []
            if config.downloadKbps > 0 { desc.append("↓\(formatSpeed(kbps: config.downloadKbps))") }
            if config.uploadKbps > 0 { desc.append("↑\(formatSpeed(kbps: config.uploadKbps))") }
            if config.latencyMs > 0 { desc.append("延迟\(config.latencyMs)ms") }
            if config.packetLoss > 0 { desc.append("丢包\(Int(config.packetLoss*100))%") }
            resultMessage = "已对 \(app.name) 应用网络限制\n\(desc.joined(separator: " / "))"
            addLog(appName: app.name, action: "应用限速", detail: desc.joined(separator: ", "))
        } else {
            // Rollback: clean up partially created pipes
            await executor.runShell("dnctl pipe \(downPipe) delete 2>/dev/null; dnctl pipe \(upPipe) delete 2>/dev/null")
            resultMessage = "限速失败: \(result.error ?? "未知错误")"
            addLog(appName: app.name, action: "限速失败", detail: result.error ?? "")
        }
        showResultAlert = true
    }

    func applyProfile(app: AppProcess, profile: NetworkProfile) async {
        await applyThrottle(app: app, config: profile.config)
    }

    // MARK: - Remove Throttle

    func removeThrottle(app: AppProcess) async {
        guard let pipes = pipeMapping[app.pid] else { return }

        let script = """
        pfctl -a \(anchorName) -F rules 2>/dev/null || true
        dnctl pipe \(pipes.downloadPipe) delete 2>/dev/null || true
        dnctl pipe \(pipes.uploadPipe) delete 2>/dev/null || true
        """

        let result = await executor.run(script, prompt: "AppThrottler: 解除 \(app.name) 限速")

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

    func removeAllThrottles() async {
        guard !pipeMapping.isEmpty else { return }
        var commands: [String] = []
        for (_, pipes) in pipeMapping {
            commands.append("dnctl pipe \(pipes.downloadPipe) delete 2>/dev/null || true")
            commands.append("dnctl pipe \(pipes.uploadPipe) delete 2>/dev/null || true")
        }
        commands.append("pfctl -a \(anchorName) -F rules 2>/dev/null || true")

        let result = await executor.run(commands.joined(separator: "\n"), prompt: "AppThrottler: 清除所有限速")

        if result.success {
            let count = throttledPIDs.count
            pipeMapping.removeAll()
            throttledPIDs.removeAll()
            addLog(appName: "全部", action: "清除限速", detail: "共 \(count) 个应用")
        }
        // If failed, don't clear in-memory state so we can retry
    }

    // MARK: - Cleanup (called on app quit)

    func cleanupAll() async {
        var commands: [String] = []
        for (_, pipes) in pipeMapping {
            commands.append("dnctl pipe \(pipes.downloadPipe) delete 2>/dev/null || true")
            commands.append("dnctl pipe \(pipes.uploadPipe) delete 2>/dev/null || true")
        }
        commands.append("pfctl -a \(anchorName) -F rules 2>/dev/null || true")
        commands.append("dnctl flush 2>/dev/null || true")
        _ = await executor.run(commands.joined(separator: "\n"), prompt: "AppThrottler: 清理所有网络规则")
        pipeMapping.removeAll()
        throttledPIDs.removeAll()
    }

    // MARK: - UID Discovery

    private func getUID(pid: Int32) async -> uid_t {
        let output = await executor.runShell("ps -o uid= -p \(pid)")
        let uidStr = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return uid_t(uidStr) ?? 0
    }

    // MARK: - Pipe Number Allocation

    private func allocatePipeNum() -> Int {
        let num = nextPipeNum
        nextPipeNum += 1
        if nextPipeNum > maxPipeNum { nextPipeNum = 100 }
        return num
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
        if kbps >= 1000 { return String(format: "%.1f Mbps", Double(kbps) / 1000.0) }
        return "\(kbps) Kbps"
    }
}
