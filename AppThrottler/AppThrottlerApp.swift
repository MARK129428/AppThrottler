import SwiftUI

@main
struct AppThrottlerEntry {
    static func main() {
        let args = CommandLine.arguments
        if args.count > 1 || args.contains("--json") {
            let runner = CLIRunner()
            runner.run()
            exit(0)
        } else {
            let app = NSApplication.shared
            let delegate = AppThrottlerDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}

class NSAppDelegateStub: NSObject, NSApplicationDelegate {}

class AppThrottlerDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let themeManager = ThemeManager.shared
        if themeManager.isCustomDark {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            NSApp.appearance = nil
        }

        let contentView = ContentView()
            .environmentObject(themeManager)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window?.center()
        window?.titlebarAppearsTransparent = false
        window?.title = "AppThrottler"
        window?.isMovableByWindowBackground = true
        window?.contentView = NSHostingView(rootView: contentView)
        window?.minSize = NSSize(width: 800, height: 500)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Setup menu bar
        setupMenuBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 AppThrottler", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "视图")
        viewMenu.addItem(NSMenuItem(title: "刷新进程列表", action: #selector(AppThrottlerDelegate.refreshProcessors), keyEquivalent: "r"))
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func refreshProcessors() {
        NotificationCenter.default.post(name: .refreshProcesses, object: nil)
    }
}

extension Notification.Name {
    static let refreshProcesses = Notification.Name("AppThrottler.RefreshProcesses")
}
