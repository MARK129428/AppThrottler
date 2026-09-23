import Foundation
import AppKit

// MARK: - Packet Data

struct CapturedPacket: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let source: String
    let destination: String
    let protocol_: String
    let length: Int
    let info: String

    var timeString: String {
        let date = Date(timeIntervalSince1970: timestamp)
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }
}

// MARK: - Capture Stats

struct CaptureStats {
    var totalPackets: Int = 0
    var totalBytes: Int = 0
    var tcpPackets: Int = 0
    var udpPackets: Int = 0
    var otherPackets: Int = 0
    var startTime: Date?

    var duration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var bytesPerSecond: Double {
        guard duration > 0 else { return 0 }
        return Double(totalBytes) / duration
    }

    var formattedRate: String {
        let bps = bytesPerSecond
        if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000) }
        if bps >= 1_000 { return String(format: "%.1f KB/s", bps / 1_000) }
        return String(format: "%.0f B/s", bps)
    }

    var formattedDuration: String {
        let d = duration
        let min = Int(d) / 60
        let sec = Int(d) % 60
        return String(format: "%02d:%02d", min, sec)
    }

    var formattedTotalBytes: String {
        let b = Double(totalBytes)
        if b >= 1_000_000_000 { return String(format: "%.2f GB", b / 1_000_000_000) }
        if b >= 1_000_000 { return String(format: "%.1f MB", b / 1_000_000) }
        if b >= 1_000 { return String(format: "%.1f KB", b / 1_000) }
        return "\(totalBytes) B"
    }
}

// MARK: - Packet Capture Manager

@MainActor
class PacketCaptureManager: ObservableObject {
    @Published var packets: [CapturedPacket] = []
    @Published var isCapturing = false
    @Published var stats = CaptureStats()
    @Published var captureError: String?
    @Published var filterText: String = ""

    private var captureProcess: Process?
    private var outputPipe: Pipe?
    private var capturedApp: AppProcess?
    private var maxPackets = 10000
    private var pcapFilePath: String?

    var filteredPackets: [CapturedPacket] {
        if filterText.isEmpty { return packets }
        let filter = filterText.lowercased()
        return packets.filter {
            $0.source.lowercased().contains(filter) ||
            $0.destination.lowercased().contains(filter) ||
            $0.protocol_.lowercased().contains(filter) ||
            $0.info.lowercased().contains(filter)
        }
    }

    // MARK: - Start Capture

    func startCapture(app: AppProcess) {
        stopCapture()

        capturedApp = app
        let connections = getProcessConnections(pid: app.pid)
        guard !connections.isEmpty else {
            captureError = "未找到 \(app.name) 的活跃网络连接。请先使用应用联网。"
            return
        }

        // Build BPF filter from connections
        let filter = buildBPFFilter(connections: connections)

        // Create pcap output path
        let tmpDir = NSTemporaryDirectory()
        let filename = "appthrottler_\(app.name)_\(Int(Date().timeIntervalSince1970)).pcap"
        pcapFilePath = tmpDir + filename

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")
        process.arguments = [
            "-i", "any",        // all interfaces
            "-nn",              // don't resolve names
            "-l",               // line buffered
            "-tt",              // raw timestamps
            "-vv",              // verbose
            "-w", pcapFilePath!, // write pcap file
            filter
        ]

        // Also spawn a reader process for real-time display
        let displayProcess = Process()
        displayProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")
        displayProcess.arguments = [
            "-i", "any",
            "-nn",
            "-l",
            "-tt",
            "-r", pcapFilePath!
        ]

        let pipe = Pipe()
        displayProcess.standardOutput = pipe

        // We'll read pcap via a separate process that tails the file
        // Actually, better approach: use tcpdump with -w for pcap AND a separate reader
        // Let's use tcpdump twice: one writes pcap, one reads it live

        // Simpler: just pipe tcpdump stdout directly
        let liveProcess = Process()
        liveProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")
        liveProcess.arguments = [
            "-i", "any",
            "-nn",
            "-l",
            "-vv",
            filter
        ]

        let livePipe = Pipe()
        liveProcess.standardOutput = livePipe
        liveProcess.standardError = Pipe()

        // Also save to pcap in background
        let saveProcess = Process()
        saveProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")
        saveProcess.arguments = [
            "-i", "any",
            "-nn",
            "-w", pcapFilePath!,
            filter
        ]
        saveProcess.standardError = Pipe()

        // Read live output
        let handle = livePipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.processOutput(line)
            }
        }

        do {
            // Start via authorized execution since tcpdump needs root
            // We'll use the same privilege escalation approach
            try liveProcess.run()
            try saveProcess.run()
        } catch {
            captureError = "启动抓包失败: \(error.localizedDescription)"
            return
        }

        captureProcess = liveProcess
        outputPipe = livePipe
        isCapturing = true
        packets = []
        stats = CaptureStats(startTime: Date())
        captureError = nil
    }

    // MARK: - Start Capture (with sudo via AppleScript)

    func startCaptureWithPrivileges(app: AppProcess) {
        stopCapture()

        capturedApp = app
        let connections = getProcessConnections(pid: app.pid)
        guard !connections.isEmpty else {
            captureError = "未找到 \(app.name) 的活跃网络连接。请先使用应用联网。"
            return
        }

        let filter = buildBPFFilter(connections: connections)

        // Create pcap output path
        let tmpDir = NSTemporaryDirectory()
        let filename = "appthrottler_\(app.name.replacingOccurrences(of: " ", with: "_"))_\(Int(Date().timeIntervalSince1970)).pcap"
        pcapFilePath = tmpDir + filename

        // Write capture script
        let captureScript = """
        #!/bin/bash
        /usr/sbin/tcpdump -i any -nn -l -tt -w "\(pcapFilePath!)" \(filter) 2>/dev/null &
        echo $!
        """

        let scriptPath = tmpDir + "appthrottler_capture.sh"
        try? captureScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let appleScript = """
        do shell script "\(scriptPath)" with administrator privileges with prompt "AppThrottler 需要管理员权限来抓取 \(app.name) 的网络数据包"
        """

        var error: NSDictionary?
        if let script = NSAppleScript(source: appleScript) {
            let _ = script.executeAndReturnError(&error)
            if let err = error {
                captureError = "权限被拒绝: \(err[NSAppleScript.errorMessage] as? String ?? "未知错误")"
                return
            }
        }

        // Start a reader process that reads the pcap file
        startPcapReader()

        isCapturing = true
        packets = []
        stats = CaptureStats(startTime: Date())
        captureError = nil
    }

    private func startPcapReader() {
        guard let pcapPath = pcapFilePath else { return }

        // Wait a moment for pcap file to be created
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            let reader = Process()
            reader.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")
            reader.arguments = ["-nn", "-l", "-tt", "-r", pcapPath]

            let pipe = Pipe()
            reader.standardOutput = pipe
            reader.standardError = Pipe()

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.processOutput(text)
                }
            }

            do {
                try reader.run()
                Task { @MainActor [weak self] in
                    self?.captureProcess = reader
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.captureError = "读取 pcap 失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Stop Capture

    func stopCapture() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        captureProcess?.terminate()
        captureProcess = nil
        outputPipe = nil
        isCapturing = false
        capturedApp = nil

        // Kill any lingering tcpdump processes
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProcess.arguments = ["-f", "appthrottler"]
        try? killProcess.run()
    }

    // MARK: - Parse Output

    private func processOutput(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            guard !line.isEmpty else { continue }
            if let packet = parsePacketLine(line) {
                packets.append(packet)
                updateStats(packet: packet)

                // Keep bounded
                if packets.count > maxPackets {
                    packets.removeFirst(packets.count - maxPackets)
                }
            }
        }
    }

    private func parsePacketLine(_ line: String) -> CapturedPacket? {
        // tcpdump -tt -nn -vv output format:
        // 1234567890.123456 IP (tos 0x0, ttl 64, id 12345, offset 0, flags [DF], proto TCP (6), length 100)
        //     192.168.1.1.80 > 10.0.0.1.52345: Flags [P.], cksum 0x1234, seq 1:100, ack 100, win 65535, length 99

        let components = line.split(separator: " ", maxSplits: 5).map(String.init)
        guard components.count >= 2 else { return nil }

        var timestamp = Date().timeIntervalSince1970
        if let ts = Double(components[0]) {
            timestamp = ts
        }

        // Match IP.port > IP.port pattern using NSRegularExpression
        let pattern = "(\\d+\\.\\d+\\.\\d+\\.\\d+)\\.(\\d+)\\s*>\\s*(\\d+\\.\\d+\\.\\d+\\.\\d+)\\.(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }

        let srcIP = nsLine.substring(with: match.range(at: 1))
        let srcPort = nsLine.substring(with: match.range(at: 2))
        let dstIP = nsLine.substring(with: match.range(at: 3))
        let dstPort = nsLine.substring(with: match.range(at: 4))

        let proto = detectProtocol(line)
        let length = extractLength(from: line)

        return CapturedPacket(
            timestamp: timestamp,
            source: "\(srcIP):\(srcPort)",
            destination: "\(dstIP):\(dstPort)",
            protocol_: proto,
            length: length,
            info: extractInfo(from: line, proto: proto)
        )
    }

    private func detectProtocol(_ line: String) -> String {
        if line.contains("proto TCP") || line.contains("Flags [") { return "TCP" }
        if line.contains("proto UDP") || line.contains("UDP,") { return "UDP" }
        if line.contains("ICMP") { return "ICMP" }
        if line.contains("ARP") { return "ARP" }
        if line.contains("DNS") { return "DNS" }
        return "OTHER"
    }

    private func extractLength(from line: String) -> Int {
        // Look for "length N"
        if let range = line.range(of: "length ") {
            let after = line[range.upperBound...]
            let numStr = after.prefix { $0.isNumber }
            return Int(numStr) ?? 0
        }
        // Look for "length: N"
        if let range = line.range(of: "length: ") {
            let after = line[range.upperBound...]
            let numStr = after.prefix { $0.isNumber }
            return Int(numStr) ?? 0
        }
        return 0
    }

    private func extractInfo(from line: String, proto: String) -> String {
        if proto == "TCP" {
            // Extract flags
            if let range = line.range(of: "Flags [") {
                let after = line[range.upperBound...]
                if let endRange = after.range(of: "]") {
                    let flags = String(after[..<endRange.lowerBound])
                    var parts = ["Flags [\(flags)]"]
                    // Extract seq/ack
                    if let seqRange = line.range(of: "seq ") {
                        let seqAfter = line[seqRange.upperBound...]
                        let seq = seqAfter.prefix { $0.isNumber || $0 == ":" }
                        parts.append("seq \(seq)")
                    }
                    if let ackRange = line.range(of: "ack ") {
                        let ackAfter = line[ackRange.upperBound...]
                        let ack = ackAfter.prefix { $0.isNumber }
                        parts.append("ack \(ack)")
                    }
                    return parts.joined(separator: " ")
                }
            }
        } else if proto == "UDP" {
            if let range = line.range(of: "UDP,") {
                let after = line[range.upperBound...]
                return "UDP " + after.prefix(40).trimmingCharacters(in: .whitespaces)
            }
        }
        return String(line.prefix(80))
    }

    // MARK: - Stats

    private func updateStats(packet: CapturedPacket) {
        stats.totalPackets += 1
        stats.totalBytes += packet.length
        switch packet.protocol_ {
        case "TCP": stats.tcpPackets += 1
        case "UDP": stats.udpPackets += 1
        default: stats.otherPackets += 1
        }
    }

    // MARK: - Network Connection Discovery

    private func getProcessConnections(pid: Int32) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "-n", "-P", "-p", "\(pid)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var ports = Set<String>()
        var hosts = Set<String>()

        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 9 else { continue }

            let netField = cols[8]
            let parts = netField.components(separatedBy: "->")

            // Local port
            let localParts = parts[0].components(separatedBy: ":")
            if let port = localParts.last, port != "*" {
                ports.insert(port)
            }

            // Remote host
            if parts.count >= 2 {
                let remoteParts = parts[1].components(separatedBy: ":")
                if remoteParts.count >= 2 {
                    let host = remoteParts.dropLast().joined(separator: ":")
                    if !host.isEmpty && host != "*" {
                        hosts.insert(host)
                    }
                }
            }
        }

        return Array(ports) + Array(hosts)
    }

    private func buildBPFFilter(connections: [String]) -> String {
        // connections can be ports or IP addresses
        var portFilters: [String] = []
        var hostFilters: [String] = []

        for conn in connections {
            if Int(conn) != nil {
                portFilters.append("port \(conn)")
            } else if conn.contains(".") {
                hostFilters.append("host \(conn)")
            }
        }

        let filters = portFilters + hostFilters
        if filters.isEmpty { return "" }

        // BPF filter: "port 80 or port 443 or host 1.2.3.4"
        return filters.joined(separator: " or ")
    }

    // MARK: - Export

    func exportPcap(to url: URL) {
        guard let pcapPath = pcapFilePath,
              FileManager.default.fileExists(atPath: pcapPath) else { return }
        try? FileManager.default.copyItem(atPath: pcapPath, toPath: url.path)
    }

    func savePcap() -> String? {
        return pcapFilePath
    }
}
