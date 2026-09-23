import Foundation

// MARK: - CLI Runner (no @MainActor dependency)

class CLIRunner {
    func run() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            printUsage()
            exit(1)
        }

        let command = args[1]
        switch command {
        case "list": listApps()
        case "apply": applyFromArgs()
        case "remove": print("Remove requires --pid"); exit(1)
        case "remove-all": removeAll()
        case "status": showStatus()
        case "capture": captureFromArgs()
        case "help", "--help", "-h": printUsage()
        default:
            fputs("Unknown command: \(command)\n", stderr)
            exit(1)
        }
    }

    // MARK: - List

    private func listApps() {
        let apps = getRunningApps()
        print("PID\tName")
        print("───\t────")
        for app in apps {
            print("\(app.pid)\t\(app.name)")
        }
        print("\nTotal: \(apps.count) processes")
    }

    // MARK: - Apply

    private func applyFromArgs() {
        guard let pidStr = getArg("pid"), let pid = Int32(pidStr) else {
            fputs("Missing --pid\n", stderr); exit(1)
        }
        let down = Int(getArg("download") ?? "0") ?? 0
        let up = Int(getArg("upload") ?? "0") ?? 0
        let latency = Int(getArg("latency") ?? "0") ?? 0
        let loss = Double(getArg("loss") ?? "0") ?? 0

        guard down > 0 || up > 0 || latency > 0 || loss > 0 else {
            fputs("Set at least one of: --download, --upload, --latency, --loss\n", stderr); exit(1)
        }

        // Find process ports via lsof
        let ports = getProcessPorts(pid: pid)
        guard !ports.isEmpty else {
            fputs("No network connections found for PID \(pid)\n", stderr); exit(1)
        }

        // Build dnctl pipe commands
        let downPipe = 100 + Int(pid) % 900
        let upPipe = downPipe + 1

        var cmds: [String] = []
        if down > 0 || latency > 0 || loss > 0 {
            var cfg = "bw \(down > 0 ? "\(down)Kbit/s" : "1Gbit/s")"
            if latency > 0 { cfg += " delay \(latency)" }
            if loss > 0 { cfg += " plr \(String(format: "%.4f", loss))" }
            cmds.append("dnctl pipe \(downPipe) config \(cfg)")
        }
        if up > 0 || latency > 0 || loss > 0 {
            var cfg = "bw \(up > 0 ? "\(up)Kbit/s" : "1Gbit/s")"
            if latency > 0 { cfg += " delay \(latency)" }
            if loss > 0 { cfg += " plr \(String(format: "%.4f", loss))" }
            cmds.append("dnctl pipe \(upPipe) config \(cfg)")
        }

        // Build PF rules
        var pfRules = ""
        for port in ports {
            if down > 0 || latency > 0 || loss > 0 {
                pfRules += "pass in quick proto tcp from any to any port \(port) dnpipe \(downPipe)\n"
            }
            if up > 0 || latency > 0 || loss > 0 {
                pfRules += "pass out quick proto tcp from any to any port \(port) dnpipe \(upPipe)\n"
            }
        }

        let script = """
        pfctl -a appthrottler -F rules 2>/dev/null || true
        \(cmds.joined(separator: "\n"))
        (echo 'rdr-anchor "appthrottler"'; echo 'anchor "appthrottler"') | pfctl -f - 2>/dev/null
        echo '\(pfRules)' | pfctl -a appthrottler -f -
        """

        runPrivileged(script, prompt: "AppThrottler: apply throttle to PID \(pid)")
        print("Throttle applied to PID \(pid)")
        var desc: [String] = []
        if down > 0 { desc.append("↓\(down)Kbps") }
        if up > 0 { desc.append("↑\(up)Kbps") }
        if latency > 0 { desc.append("delay:\(latency)ms") }
        if loss > 0 { desc.append("loss:\(Int(loss*100))%") }
        print(desc.joined(separator: " "))
    }

    // MARK: - Remove All

    private func removeAll() {
        let script = """
        pfctl -a appthrottler -F rules 2>/dev/null || true
        dnctl flush 2>/dev/null || true
        """
        runPrivileged(script, prompt: "AppThrottler: remove all throttles")
        print("All throttles removed")
    }

    // MARK: - Status

    private func showStatus() {
        let result = shell("/usr/sbin/dnctl", args: ["pipe", "show"])
        if result.contains("no pipes") || result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("No active throttles")
        } else {
            print(result)
        }
    }

    // MARK: - Capture

    private func captureFromArgs() {
        guard let pidStr = getArg("pid"), let pid = Int32(pidStr) else {
            fputs("Missing --pid\n", stderr); exit(1)
        }
        let duration = Int(getArg("duration") ?? "10") ?? 10
        let ports = getProcessPorts(pid: pid)
        guard !ports.isEmpty else {
            fputs("No network connections for PID \(pid)\n", stderr); exit(1)
        }

        let filter = ports.map { "port \($0)" }.joined(separator: " or ")
        print("Capturing PID \(pid) for \(duration)s (filter: \(filter))...")
        print(String(repeating: "─", count: 80))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")
        process.arguments = ["-i", "any", "-nn", "-l", "-tt", "-c", "500", "-G", "\(duration)", "-W", "1", filter]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch {
            fputs("tcpdump failed: \(error)\n", stderr)
        }
    }

    // MARK: - Helpers

    private func getRunningApps() -> [(name: String, pid: Int32)] {
        let result = shell("/bin/ps", args: ["-axo", "pid,comm"])
        var seen = Set<String>()
        var apps: [(String, Int32)] = []

        for line in result.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            let fullPath = String(parts[1])
            let name = fullPath.components(separatedBy: "/").last ?? fullPath
            guard !name.isEmpty, !name.hasPrefix("kernel"), name != "ps" else { continue }
            guard seen.insert(name).inserted else { continue }
            apps.append((name, pid))
        }
        return apps.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private func getProcessPorts(pid: Int32) -> [String] {
        let result = shell("/usr/sbin/lsof", args: ["-i", "-n", "-P", "-p", "\(pid)"])
        var ports = Set<String>()
        for line in result.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 9 else { continue }
            let parts = cols[8].components(separatedBy: "->")
            let localParts = parts[0].components(separatedBy: ":")
            if let port = localParts.last, port != "*", Int(port) != nil {
                ports.insert(port)
            }
        }
        return Array(ports)
    }

    private func getArg(_ name: String) -> String? {
        let prefix = "--\(name)="
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }) {
            return String(arg.dropFirst(prefix.count))
        }
        if let idx = CommandLine.arguments.firstIndex(of: "--\(name)"),
           idx + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[idx + 1]
        }
        return nil
    }

    private func shell(_ path: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func runPrivileged(_ script: String, prompt: String) {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = """
        do shell script "\(escaped)" with administrator privileges with prompt "\(prompt)"
        """
        var error: NSDictionary?
        if let scriptObj = NSAppleScript(source: appleScript) {
            let _ = scriptObj.executeAndReturnError(&error)
            if let err = error {
                fputs("Error: \(err[NSAppleScript.errorMessage] as? String ?? "denied")\n", stderr)
                exit(1)
            }
        }
    }

    private func printUsage() {
        print("""
        AppThrottler CLI — Network throttling & packet capture for macOS

        USAGE:
            AppThrottler <command> [options]

        COMMANDS:
            list                              List running processes
            apply --pid <pid> [options]       Apply network throttle
            remove --pid <pid>                (use remove-all)
            remove-all                        Remove all throttles
            status                            Show active throttle pipes
            capture --pid <pid> [--duration N] Capture packets

        APPLY OPTIONS:
            --download <kbps>                 Download speed limit
            --upload <kbps>                   Upload speed limit
            --latency <ms>                    Add latency
            --loss <0.0-1.0>                  Packet loss rate

        PRESETS (use with apply):
            --preset 2g|3g|4g|5g|weak-wifi|high-speed-rail|elevator

        EXAMPLES:
            AppThrottler list
            AppThrottler apply --pid 1234 --download 1000 --latency 200
            AppThrottler apply --pid 1234 --loss 0.1
            AppThrottler capture --pid 1234 --duration 30
            AppThrottler remove-all
        """)
    }
}
