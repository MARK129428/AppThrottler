import Foundation

// MARK: - Traffic Sample

struct TrafficSample {
    let timestamp: Date
    let bytesIn: Int64
    let bytesOut: Int64
}

struct TrafficStats {
    var totalBytesIn: Int64 = 0
    var totalBytesOut: Int64 = 0
    var peakRateIn: Double = 0
    var peakRateOut: Double = 0
    var sampleCount: Int = 0
    var startTime: Date?

    var avgRateIn: Double {
        guard let start = startTime, sampleCount > 1 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return Double(totalBytesIn) / elapsed
    }

    var avgRateOut: Double {
        guard let start = startTime, sampleCount > 1 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return Double(totalBytesOut) / elapsed
    }
}

// MARK: - Traffic Monitor

@MainActor
class TrafficMonitor: ObservableObject {
    @Published var history: [TrafficSample] = []
    @Published var currentRateIn: Double = 0  // bytes/sec
    @Published var currentRateOut: Double = 0
    @Published var isMonitoring = false
    @Published var stats = TrafficStats()

    private var monitorTask: Task<Void, Never>?
    private var targetPID: Int32?
    private var maxSamples = 300  // ~5 min at 1s interval

    var formattedRateIn: String { formatBytes(currentRateIn) + "/s" }
    var formattedRateOut: String { formatBytes(currentRateOut) + "/s" }
    var formattedTotalIn: String { formatBytes(Double(stats.totalBytesIn)) }
    var formattedTotalOut: String { formatBytes(Double(stats.totalBytesOut)) }
    var formattedPeakIn: String { formatBytes(stats.peakRateIn) + "/s" }
    var formattedPeakOut: String { formatBytes(stats.peakRateOut) + "/s" }
    var formattedAvgIn: String { formatBytes(stats.avgRateIn) + "/s" }
    var formattedAvgOut: String { formatBytes(stats.avgRateOut) + "/s" }

    func startMonitoring(pid: Int32) {
        stopMonitoring()
        targetPID = pid
        isMonitoring = true
        history = []
        stats = TrafficStats(startTime: Date())

        monitorTask = Task { [weak self] in
            var lastIn: Int64 = 0
            var lastOut: Int64 = 0
            var firstSample = true

            while !Task.isCancelled {
                guard let self = self, let pid = self.targetPID else { break }
                let (bytesIn, bytesOut) = await self.readTraffic(pid: pid)

                if !firstSample && !Task.isCancelled {
                    let deltaIn = max(0, bytesIn - lastIn)
                    let deltaOut = max(0, bytesOut - lastOut)
                    let sample = TrafficSample(timestamp: Date(), bytesIn: deltaIn, bytesOut: deltaOut)

                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.history.append(sample)
                        if self.history.count > self.maxSamples {
                            self.history.removeFirst(self.history.count - self.maxSamples)
                        }
                        self.currentRateIn = Double(deltaIn)
                        self.currentRateOut = Double(deltaOut)
                        self.stats.totalBytesIn += deltaIn
                        self.stats.totalBytesOut += deltaOut
                        self.stats.sampleCount += 1
                        if Double(deltaIn) > self.stats.peakRateIn { self.stats.peakRateIn = Double(deltaIn) }
                        if Double(deltaOut) > self.stats.peakRateOut { self.stats.peakRateOut = Double(deltaOut) }
                    }
                }

                lastIn = bytesIn
                lastOut = bytesOut
                firstSample = false
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
        targetPID = nil
    }

    private func readTraffic(pid: Int32) async -> (Int64, Int64) {
        // Use nettop to get per-PID traffic
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-l", "-n", "-t", "external", "-p", "\(pid)", "-k", "time,rx,tx"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do { try process.run() } catch { return (0, 0) }

        // Wait briefly for output
        try? await Task.sleep(nanoseconds: 500_000_000)
        process.terminate()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return (0, 0) }

        var totalIn: Int64 = 0
        var totalOut: Int64 = 0

        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if cols.count >= 3 {
                totalIn += parseBytes(cols[1])
                totalOut += parseBytes(cols[2])
            }
        }

        return (totalIn, totalOut)
    }

    private func parseBytes(_ str: String) -> Int64 {
        let cleaned = str.replacingOccurrences(of: " ", with: "")
        if let val = Int64(cleaned) { return val }
        // Parse "1.2K", "3.4M" etc.
        let numStr = cleaned.prefix { $0.isNumber || $0 == "." }
        guard let num = Double(numStr) else { return 0 }
        let suffix = cleaned.dropFirst(numStr.count)
        switch suffix {
        case "K": return Int64(num * 1024)
        case "M": return Int64(num * 1024 * 1024)
        case "G": return Int64(num * 1024 * 1024 * 1024)
        default: return Int64(num)
        }
    }

    func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", bytes / 1_073_741_824) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", bytes / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.1f KB", bytes / 1024) }
        return String(format: "%.0f B", bytes)
    }
}
