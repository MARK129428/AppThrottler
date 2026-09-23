import Foundation

// MARK: - Webhook Manager

class WebhookManager: ObservableObject {
    @Published var webhookURL: String = ""
    @Published var enabled: Bool = false
    @Published var lastSentAt: Date?
    @Published var sendCount: Int = 0

    struct WebhookPayload: Codable {
        let event: String
        let appName: String
        let pid: Int32
        let timestamp: String
        let details: [String: String]
    }

    func notify(event: String, appName: String, pid: Int32, details: [String: String] = [:]) {
        guard enabled, !webhookURL.isEmpty, let url = URL(string: webhookURL) else { return }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

        let payload = WebhookPayload(
            event: event,
            appName: appName,
            pid: pid,
            timestamp: df.string(from: Date()),
            details: details
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.lastSentAt = Date()
                self?.sendCount += 1
            }
        }.resume()
    }
}

// MARK: - AppleScript Bridge

class AppleScriptBridge {
    static let shared = AppleScriptBridge()

    func handleEvent(_ event: String, params: [String: String]) -> String {
        switch event {
        case "list":
            return listApps()
        case "apply":
            guard let pidStr = params["pid"], let pid = Int32(pidStr) else {
                return "error:missing pid"
            }
            return applyThrottle(pid: pid, params: params)
        case "remove":
            guard let pidStr = params["pid"], let pid = Int32(pidStr) else {
                return "error:missing pid"
            }
            return removeThrottle(pid: pid)
        case "remove-all":
            return removeAll()
        case "status":
            return status()
        default:
            return "error:unknown event"
        }
    }

    private func listApps() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,comm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return "error:ps failed" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func applyThrottle(pid: Int32, params: [String: String]) -> String {
        let down = params["download"] ?? "0"
        let up = params["upload"] ?? "0"
        let latency = params["latency"] ?? "0"
        let loss = params["loss"] ?? "0"

        // Find ports
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-i", "-n", "-P", "-p", "\(pid)"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = Pipe()
        do { try lsof.run(); lsof.waitUntilExit() } catch { return "error:lsof failed" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return "error:no output" }

        var ports: [String] = []
        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 9 else { continue }
            let parts = cols[8].components(separatedBy: "->")
            let localParts = parts[0].components(separatedBy: ":")
            if let port = localParts.last, port != "*", Int(port) != nil, !ports.contains(port) {
                ports.append(port)
            }
        }
        guard !ports.isEmpty else { return "error:no connections" }

        let downInt = Int(down) ?? 0
        let upInt = Int(up) ?? 0
        let latencyInt = Int(latency) ?? 0
        let lossDouble = Double(loss) ?? 0

        let downPipe = 100 + Int(pid) % 900
        let upPipe = downPipe + 1

        var cmds: [String] = []
        if downInt > 0 || latencyInt > 0 || lossDouble > 0 {
            var cfg = "bw \(downInt > 0 ? "\(downInt)Kbit/s" : "1Gbit/s")"
            if latencyInt > 0 { cfg += " delay \(latencyInt)" }
            if lossDouble > 0 { cfg += " plr \(String(format: "%.4f", lossDouble))" }
            cmds.append("dnctl pipe \(downPipe) config \(cfg)")
        }
        if upInt > 0 || latencyInt > 0 || lossDouble > 0 {
            var cfg = "bw \(upInt > 0 ? "\(upInt)Kbit/s" : "1Gbit/s")"
            if latencyInt > 0 { cfg += " delay \(latencyInt)" }
            if lossDouble > 0 { cfg += " plr \(String(format: "%.4f", lossDouble))" }
            cmds.append("dnctl pipe \(upPipe) config \(cfg)")
        }

        var pfRules = ""
        for port in ports {
            if downInt > 0 || latencyInt > 0 || lossDouble > 0 {
                pfRules += "pass in quick proto tcp from any to any port \(port) dnpipe \(downPipe)\n"
            }
            if upInt > 0 || latencyInt > 0 || lossDouble > 0 {
                pfRules += "pass out quick proto tcp from any to any port \(port) dnpipe \(upPipe)\n"
            }
        }

        let script = """
        pfctl -a appthrottler -F rules 2>/dev/null || true
        \(cmds.joined(separator: "\n"))
        (echo 'rdr-anchor "appthrottler"'; echo 'anchor "appthrottler"') | pfctl -f - 2>/dev/null
        echo '\(pfRules)' | pfctl -a appthrottler -f -
        """

        let result = runShell(script)
        return result.success ? "ok" : "error:\(result.error ?? "failed")"
    }

    private func removeThrottle(pid: Int32) -> String {
        _ = runShell("pfctl -a appthrottler -F rules 2>/dev/null || true; dnctl flush 2>/dev/null || true")
        return "ok"
    }

    private func removeAll() -> String {
        _ = runShell("pfctl -a appthrottler -F rules 2>/dev/null || true; dnctl flush 2>/dev/null || true")
        return "ok"
    }

    private func status() -> String {
        let result = runShell("/usr/sbin/dnctl pipe show")
        return result.output.isEmpty ? "idle" : result.output
    }

    private func runShell(_ script: String) -> (success: Bool, output: String, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run(); process.waitUntilExit() } catch {
            return (false, "", error.localizedDescription)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8))
    }
}
