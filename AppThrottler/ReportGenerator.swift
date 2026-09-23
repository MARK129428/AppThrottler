import Foundation

struct TestReport {
    let appName: String
    let pid: Int32
    let startTime: Date
    let endTime: Date
    let throttleConfig: ThrottleConfig?
    let presetName: String?
    let trafficStats: TrafficStats?
    let capturePacketCount: Int
    let faultInjection: [String]
    let scenarioSteps: [(name: String, duration: Int)]?

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    func generateHTML() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var sections: [String] = []

        // Header
        sections.append("""
        <div class="header">
            <h1>AppThrottler 测试报告</h1>
            <p class="subtitle">\(appName) · \(df.string(from: startTime))</p>
        </div>
        """)

        // Summary
        sections.append("""
        <div class="section">
            <h2>测试概要</h2>
            <table>
                <tr><td>应用名称</td><td>\(appName)</td></tr>
                <tr><td>PID</td><td>\(pid)</td></tr>
                <tr><td>测试时长</td><td>\(formatDuration(duration))</td></tr>
                <tr><td>开始时间</td><td>\(df.string(from: startTime))</td></tr>
                <tr><td>结束时间</td><td>\(df.string(from: endTime))</td></tr>
                \(presetName.map { "<tr><td>网络预设</td><td>\($0)</td></tr>" } ?? "")
            </table>
        </div>
        """)

        // Throttle config
        if let config = throttleConfig, !config.isUnlimited {
            var rows: [String] = []
            if config.downloadKbps > 0 { rows.append("<tr><td>下载限速</td><td>\(config.downloadKbps) Kbps</td></tr>") }
            if config.uploadKbps > 0 { rows.append("<tr><td>上传限速</td><td>\(config.uploadKbps) Kbps</td></tr>") }
            if config.latencyMs > 0 { rows.append("<tr><td>延迟注入</td><td>\(config.latencyMs) ms</td></tr>") }
            if config.packetLoss > 0 { rows.append("<tr><td>丢包率</td><td>\(Int(config.packetLoss * 100))%</td></tr>") }
            sections.append("""
            <div class="section">
                <h2>限速配置</h2>
                <table>\(rows.joined())</table>
            </div>
            """)
        }

        // Traffic stats
        if let stats = trafficStats, stats.sampleCount > 0 {
            sections.append("""
            <div class="section">
                <h2>流量统计</h2>
                <table>
                    <tr><td>总下载</td><td>\(formatBytes(Double(stats.totalBytesIn)))</td></tr>
                    <tr><td>总上传</td><td>\(formatBytes(Double(stats.totalBytesOut)))</td></tr>
                    <tr><td>平均下载速率</td><td>\(formatBytes(stats.avgRateIn))/s</td></tr>
                    <tr><td>平均上传速率</td><td>\(formatBytes(stats.avgRateOut))/s</td></tr>
                    <tr><td>峰值下载速率</td><td>\(formatBytes(stats.peakRateIn))/s</td></tr>
                    <tr><td>峰值上传速率</td><td>\(formatBytes(stats.peakRateOut))/s</td></tr>
                    <tr><td>采样数</td><td>\(stats.sampleCount)</td></tr>
                </table>
            </div>
            """)
        }

        // Fault injection
        if !faultInjection.isEmpty {
            sections.append("""
            <div class="section">
                <h2>故障注入</h2>
                <ul>\(faultInjection.map { "<li>\($0)</li>" }.joined())</ul>
            </div>
            """)
        }

        // Scenario steps
        if let steps = scenarioSteps, !steps.isEmpty {
            let rows = steps.enumerated().map { i, step in
                "<tr><td>\(i + 1)</td><td>\(step.name)</td><td>\(step.duration)s</td></tr>"
            }.joined()
            sections.append("""
            <div class="section">
                <h2>场景编排</h2>
                <table><tr><th>步骤</th><th>名称</th><th>时长</th></tr>\(rows)</table>
            </div>
            """)
        }

        // Packet capture summary
        if capturePacketCount > 0 {
            sections.append("""
            <div class="section">
                <h2>抓包摘要</h2>
                <table>
                    <tr><td>捕获数据包</td><td>\(capturePacketCount) 个</td></tr>
                    <tr><td>pcap 文件</td><td>可通过 Wireshark 打开分析</td></tr>
                </table>
            </div>
            """)
        }

        return wrapHTML(sections.joined(separator: "\n"))
    }

    private func wrapHTML(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
            <meta charset="UTF-8">
            <title>AppThrottler 测试报告 - \(appName)</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { font-family: -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif; background: #f5f5f7; color: #1d1d1f; padding: 40px; }
                .header { text-align: center; margin-bottom: 40px; }
                .header h1 { font-size: 28px; font-weight: 700; }
                .header .subtitle { color: #86868b; margin-top: 8px; font-size: 14px; }
                .section { background: #fff; border-radius: 12px; padding: 24px; margin-bottom: 20px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
                .section h2 { font-size: 18px; font-weight: 600; margin-bottom: 16px; color: #1d1d1f; border-bottom: 1px solid #e8e8ed; padding-bottom: 8px; }
                table { width: 100%; border-collapse: collapse; }
                td, th { padding: 10px 12px; text-align: left; border-bottom: 1px solid #f0f0f5; font-size: 14px; }
                td:first-child { color: #86868b; width: 160px; }
                th { background: #f9f9fb; font-weight: 600; color: #6e6e73; }
                ul { padding-left: 20px; }
                li { padding: 4px 0; font-size: 14px; }
                .footer { text-align: center; color: #86868b; font-size: 12px; margin-top: 40px; }
            </style>
        </head>
        <body>
            \(body)
            <p class="footer">Generated by AppThrottler · \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))</p>
        </body>
        </html>
        """
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.2f GB", bytes / 1_073_741_824) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", bytes / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.1f KB", bytes / 1024) }
        return String(format: "%.0f B", bytes)
    }
}

// MARK: - Report Generator

class ReportGenerator {
    static func saveReport(_ report: TestReport, to url: URL) {
        let html = report.generateHTML()
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }

    static func saveReport(_ report: TestReport) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let reportsDir = dir.appendingPathComponent("AppThrottler/Reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "report_\(report.appName)_\(df.string(from: Date())).html"
        let url = reportsDir.appendingPathComponent(filename)
        saveReport(report, to: url)
        return url
    }
}
