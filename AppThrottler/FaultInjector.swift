import Foundation

// MARK: - Fault Types

enum FaultType: String, CaseIterable, Identifiable {
    case dnsTimeout = "DNS 超时"
    case dnsFail = "DNS 解析失败"
    case dnsHijack = "DNS 劫持"
    case tcpReset = "TCP 连接重置"
    case sslError = "HTTPS 证书错误"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dnsTimeout: return "clock.badge.exclamationmark"
        case .dnsFail: return "globe.badge.chevron.backward"
        case .dnsHijack: return "point.3.filled.connected.trianglepath.dotted"
        case .tcpReset: return "xmark.rectangle.fill"
        case .sslError: return "lock.slash"
        }
    }

    var description: String {
        switch self {
        case .dnsTimeout: return "DNS 查询超时（5s），测试 DNS 重试逻辑"
        case .dnsFail: return "所有 DNS 查询返回 NXDOMAIN，测试离线 DNS 缓存"
        case .dnsHijack: return "DNS 解析被劫持到 127.0.0.1，测试证书 pinning"
        case .tcpReset: return "TCP 连接建立后立即收到 RST，测试重连机制"
        case .sslError: return "HTTPS 握手失败，测试证书校验和降级逻辑"
        }
    }

    var color: String {
        switch self {
        case .dnsTimeout: return "orange"
        case .dnsFail: return "red"
        case .dnsHijack: return "purple"
        case .tcpReset: return "red"
        case .sslError: return "red"
        }
    }
}

// MARK: - Fault Injector

@MainActor
class FaultInjector: ObservableObject {
    @Published var activeFaults: Set<FaultType> = []
    @Published var showResult = false
    @Published var resultMessage = ""

    func isActive(_ fault: FaultType) -> Bool {
        activeFaults.contains(fault)
    }

    func toggle(fault: FaultType) {
        if isActive(fault) {
            deactivate(fault: fault)
        } else {
            activate(fault: fault)
        }
    }

    func activate(fault: FaultType) {
        var script = ""

        switch fault {
        case .dnsTimeout:
            // Block DNS port 53 traffic with high delay
            script = """
            # Add PF rule to drop DNS traffic (simulating timeout)
            echo 'block drop out quick proto udp from any to any port 53' | pfctl -a appthrottler/fault -f - 2>/dev/null || \
            (echo 'anchor "appthrottler/fault"' | pfctl -a appthrottler -f - 2>/dev/null; \
             echo 'block drop out quick proto udp from any to any port 53' | pfctl -a appthrottler/fault -f -)
            """

        case .dnsFail:
            // Return NXDOMAIN via /etc/hosts override
            script = """
            # Backup hosts file and add poison entries
            cp /etc/hosts /etc/hosts.appthrottler.bak 2>/dev/null || true
            echo '## AppThrottler DNS Fail
            0.0.0.0 *
            255.255.255.255 *' >> /etc/hosts
            dscacheutil -flushcache
            """

        case .dnsHijack:
            // Redirect DNS to localhost
            script = """
            cp /etc/hosts /etc/hosts.appthrottler.bak 2>/dev/null || true
            echo '## AppThrottler DNS Hijack
            127.0.0.1 google.com
            127.0.0.1 apple.com
            127.0.0.1 facebook.com
            127.0.0.1 github.com
            127.0.0.1 amazon.com
            127.0.0.1 cloudflare.com' >> /etc/hosts
            dscacheutil -flushcache
            """

        case .tcpReset:
            // Use PF to send RST on matching TCP connections
            script = """
            echo 'block return out quick proto tcp from any to any' | pfctl -a appthrottler/fault -f - 2>/dev/null || \
            (echo 'anchor "appthrottler/fault"' | pfctl -a appthrottler -f - 2>/dev/null; \
             echo 'block return out quick proto tcp from any to any' | pfctl -a appthrottler/fault -f -)
            """

        case .sslError:
            // Block HTTPS port 443
            script = """
            echo 'block drop out quick proto tcp from any to any port 443' | pfctl -a appthrottler/fault -f - 2>/dev/null || \
            (echo 'anchor "appthrottler/fault"' | pfctl -a appthrottler -f - 2>/dev/null; \
             echo 'block drop out quick proto tcp from any to any port 443' | pfctl -a appthrottler/fault -f -)
            """
        }

        let result = runPrivileged(script, prompt: "AppThrottler: 启用故障注入 - \(fault.rawValue)")
        if result.success {
            activeFaults.insert(fault)
            resultMessage = "已启用: \(fault.rawValue)"
        } else {
            resultMessage = "启用失败: \(result.error ?? "权限被拒绝")"
        }
        showResult = true
    }

    func deactivate(fault: FaultType) {
        var script = ""

        switch fault {
        case .dnsTimeout, .tcpReset, .sslError:
            script = "pfctl -a appthrottler/fault -F rules 2>/dev/null || true"
        case .dnsFail, .dnsHijack:
            script = """
            if [ -f /etc/hosts.appthrottler.bak ]; then
                cp /etc/hosts.appthrottler.bak /etc/hosts
                rm /etc/hosts.appthrottler.bak
            fi
            dscacheutil -flushcache
            """
        }

        let result = runPrivileged(script, prompt: "AppThrottler: 停用故障注入 - \(fault.rawValue)")
        if result.success {
            activeFaults.remove(fault)
            resultMessage = "已停用: \(fault.rawValue)"
        } else {
            resultMessage = "停用失败: \(result.error ?? "权限被拒绝")"
        }
        showResult = true
    }

    func deactivateAll() {
        let script = """
        pfctl -a appthrottler/fault -F rules 2>/dev/null || true
        if [ -f /etc/hosts.appthrottler.bak ]; then
            cp /etc/hosts.appthrottler.bak /etc/hosts
            rm /etc/hosts.appthrottler.bak
        fi
        dscacheutil -flushcache
        """
        _ = runPrivileged(script, prompt: "AppThrottler: 停用所有故障注入")
        activeFaults.removeAll()
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
