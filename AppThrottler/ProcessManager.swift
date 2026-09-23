import Foundation
import AppKit

struct AppProcess: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let pid: Int32
    let bundleIdentifier: String?
    let icon: NSImage?
    let executablePath: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    static func == (lhs: AppProcess, rhs: AppProcess) -> Bool {
        lhs.pid == rhs.pid
    }
}

@MainActor
class ProcessManager: ObservableObject {
    @Published var apps: [AppProcess] = []

    func refresh() {
        var seen = Set<String>()
        var result: [AppProcess] = []

        // Use NSWorkspace for GUI apps
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
            guard seen.insert(name).inserted else { continue }

            let process = AppProcess(
                name: name,
                pid: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                icon: app.icon,
                executablePath: app.executableURL?.path
            )
            result.append(process)
        }

        // Also show daemon/CLI processes if they have a name
        let allPids = getAllPids()
        for pid in allPids {
            guard pid > 0 else { continue }
            if result.contains(where: { $0.pid == pid }) { continue }

            let name = getProcessName(pid: pid)
            guard !name.isEmpty, !name.hasPrefix("kernel"), name != "launchd" else { continue }
            guard seen.insert(name).inserted else { continue }

            let process = AppProcess(
                name: name,
                pid: pid,
                bundleIdentifier: nil,
                icon: nil,
                executablePath: getProcessPath(pid: pid)
            )
            result.append(process)
        }

        apps = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func getAllPids() -> [Int32] {
        var size = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        return procs.prefix(actualCount).map { $0.kp_proc.p_pid }
    }

    private func getProcessName(pid: Int32) -> String {
        var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        proc_name(pid, &name, UInt32(MAXPATHLEN))
        return String(cString: name)
    }

    private func getProcessPath(pid: Int32) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &path, UInt32(MAXPATHLEN))
        guard result > 0 else { return nil }
        return String(cString: path)
    }
}
