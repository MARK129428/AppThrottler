import Foundation

// MARK: - Throttle Config

struct ThrottleConfig: Codable, Equatable {
    var downloadKbps: Int = 0       // 0 = unlimited
    var uploadKbps: Int = 0
    var latencyMs: Int = 0          // 0 = no delay
    var packetLoss: Double = 0.0    // 0.0 ~ 1.0

    var isUnlimited: Bool {
        downloadKbps == 0 && uploadKbps == 0 && latencyMs == 0 && packetLoss == 0
    }
}

// MARK: - Network Profile (Preset)

struct NetworkProfile: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let category: Category
    let config: ThrottleConfig

    enum Category: String, Codable, CaseIterable {
        case cellular = "移动网络"
        case wifi = "WiFi"
        case scenario = "测试场景"
        case custom = "自定义"
    }
}

// MARK: - Built-in Presets

extension NetworkProfile {
    static let presets: [NetworkProfile] = [
        // Cellular
        NetworkProfile(
            id: "2g", name: "2G (GPRS)", icon: "antenna.radiowaves.left.and.right",
            description: "50 Kbps 下载 / 20 Kbps 上传 / 500ms 延迟",
            category: .cellular,
            config: ThrottleConfig(downloadKbps: 50, uploadKbps: 20, latencyMs: 500, packetLoss: 0.02)
        ),
        NetworkProfile(
            id: "3g", name: "3G", icon: "antenna.radiowaves.left.and.right",
            description: "1 Mbps 下载 / 384 Kbps 上传 / 200ms 延迟",
            category: .cellular,
            config: ThrottleConfig(downloadKbps: 1000, uploadKbps: 384, latencyMs: 200, packetLoss: 0.01)
        ),
        NetworkProfile(
            id: "4g", name: "4G LTE", icon: "antenna.radiowaves.left.and.right",
            description: "10 Mbps 下载 / 5 Mbps 上传 / 50ms 延迟",
            category: .cellular,
            config: ThrottleConfig(downloadKbps: 10000, uploadKbps: 5000, latencyMs: 50, packetLoss: 0.005)
        ),
        NetworkProfile(
            id: "5g", name: "5G", icon: "antenna.radiowaves.left.and.right",
            description: "100 Mbps 下载 / 50 Mbps 上传 / 10ms 延迟",
            category: .cellular,
            config: ThrottleConfig(downloadKbps: 100000, uploadKbps: 50000, latencyMs: 10, packetLoss: 0.001)
        ),

        // WiFi
        NetworkProfile(
            id: "weak-wifi", name: "弱 WiFi", icon: "wifi.exclamationmark",
            description: "500 Kbps 下载 / 200 Kbps 上传 / 300ms 延迟 / 10% 丢包",
            category: .wifi,
            config: ThrottleConfig(downloadKbps: 500, uploadKbps: 200, latencyMs: 300, packetLoss: 0.10)
        ),
        NetworkProfile(
            id: "coffee-wifi", name: "咖啡厅 WiFi", icon: "cup.and.saucer.fill",
            description: "5 Mbps 下载 / 2 Mbps 上传 / 80ms 延迟 / 3% 丢包",
            category: .wifi,
            config: ThrottleConfig(downloadKbps: 5000, uploadKbps: 2000, latencyMs: 80, packetLoss: 0.03)
        ),

        // Test Scenarios
        NetworkProfile(
            id: "high-speed-rail", name: "高铁", icon: "tram.fill",
            description: "频繁切换基站，间歇性断连 / 500ms 延迟 / 20% 丢包",
            category: .scenario,
            config: ThrottleConfig(downloadKbps: 2000, uploadKbps: 1000, latencyMs: 500, packetLoss: 0.20)
        ),
        NetworkProfile(
            id: "elevator", name: "电梯", icon: "rectangle.compress.vertical",
            description: "极弱信号 / 100 Kbps / 1000ms 延迟 / 30% 丢包",
            category: .scenario,
            config: ThrottleConfig(downloadKbps: 100, uploadKbps: 50, latencyMs: 1000, packetLoss: 0.30)
        ),
        NetworkProfile(
            id: "packet-loss-heavy", name: "严重丢包", icon: "exclamationmark.triangle.fill",
            description: "不限速但 40% 丢包，测试重传机制",
            category: .scenario,
            config: ThrottleConfig(downloadKbps: 0, uploadKbps: 0, latencyMs: 0, packetLoss: 0.40)
        ),
        NetworkProfile(
            id: "high-latency", name: "高延迟", icon: "hourglass",
            description: "不限速但 2000ms 延迟，测试超时逻辑",
            category: .scenario,
            config: ThrottleConfig(downloadKbps: 0, uploadKbps: 0, latencyMs: 2000, packetLoss: 0.0)
        ),
    ]
}
