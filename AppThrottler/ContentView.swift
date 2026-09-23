import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var processManager = ProcessManager()
    @StateObject private var throttleManager = ThrottleManager()
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var scenarioEngine: ScenarioEngine
    @StateObject private var packetCapture = PacketCaptureManager()
    @StateObject private var trafficMonitor = TrafficMonitor()
    @StateObject private var faultInjector = FaultInjector()
    @StateObject private var webhookManager = WebhookManager()
    @StateObject private var httpInspector = HTTPInspector()
    @StateObject private var serverManager = ServerManager()
    @StateObject private var proxyServer = ProxyServer()
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    @State private var selectedApp: AppProcess?
    @State private var searchText: String = ""
    @State private var selectedTab: RightTab = .manual
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    enum RightTab: String, CaseIterable, Identifiable {
        case manual = "手动设置"
        case presets = "网络预设"
        case traffic = "流量监控"
        case faults = "故障注入"
        case scenarios = "场景编排"
        case capture = "抓包"
        case http = "HTTP调试"
        case profiles = "测试配置"
        case report = "测试报告"
        case proxy = "iPhone代理"
        case settings = "设置"
        case log = "操作日志"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .manual: return "slider.horizontal.3"
            case .presets: return "antenna.radiowaves.left.and.right"
            case .traffic: return "chart.line.uptrend.xyaxis"
            case .faults: return "exclamationmark.triangle"
            case .scenarios: return "play.rectangle.on.rectangle"
            case .capture: return "camera.metering.spot"
            case .http: return "network"
            case .profiles: return "tray.full"
            case .report: return "doc.text"
            case .proxy: return "iphone.radiowaves.left.and.right"
            case .settings: return "gearshape"
            case .log: return "list.bullet.rectangle"
            }
        }
    }

    init() {
        let tm = ThrottleManager()
        _throttleManager = StateObject(wrappedValue: tm)
        _scenarioEngine = StateObject(wrappedValue: ScenarioEngine(throttleManager: tm))
        _processManager = StateObject(wrappedValue: ProcessManager())
        _profileManager = StateObject(wrappedValue: ProfileManager())
        _packetCapture = StateObject(wrappedValue: PacketCaptureManager())
        _trafficMonitor = StateObject(wrappedValue: TrafficMonitor())
        _faultInjector = StateObject(wrappedValue: FaultInjector())
        _webhookManager = StateObject(wrappedValue: WebhookManager())
    }

    var filteredApps: [AppProcess] {
        if searchText.isEmpty { return processManager.apps }
        return processManager.apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // ── Sidebar: Process List ──
            List(filteredApps, selection: $selectedApp) { app in
                AppRow(app: app, throttleManager: throttleManager)
                    .tag(app)
            }
            .listStyle(.sidebar)
            .navigationTitle("应用")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
            .searchable(text: $searchText, placement: .sidebar, prompt: "搜索应用...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { processManager.refresh() } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .help("刷新进程列表 (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        } detail: {
            // ── Detail: Tool Panels ──
            if let app = selectedApp {
                detailView(app: app)
                    .navigationTitle(app.name)
                    .navigationSubtitle("PID \(app.pid)")
            } else {
                emptyState
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(theme.windowBackground)
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !throttleManager.throttledPIDs.isEmpty {
                    Button {
                        throttleManager.removeAllThrottles()
                    } label: {
                        Label("清除全部限速", systemImage: "xmark.circle.fill")
                    }
                    .tint(theme.error)
                    .help("清除所有应用的限速")
                }
            }
            ToolbarItem(placement: .automatic) {
                if let app = selectedApp, throttleManager.isThrottled(pid: app.pid) {
                    Button {
                        throttleManager.removeThrottle(app: app)
                    } label: {
                        Label("解除限速", systemImage: "bolt.slash")
                    }
                    .tint(theme.warning)
                }
            }
        }
        .onAppear { processManager.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .refreshProcesses)) { _ in
            processManager.refresh()
        }
        .alert("操作结果", isPresented: $throttleManager.showResultAlert) {
            Button("好的") { throttleManager.showResultAlert = false }
        } message: {
            Text(throttleManager.resultMessage)
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private func detailView(app: AppProcess) -> some View {
        VStack(spacing: 0) {
            // Tab bar as segmented control (native macOS style)
            Picker("功能", selection: $selectedTab) {
                ForEach(RightTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Tab content with transition animation
            Group {
                switch selectedTab {
                case .manual:
                    ManualSettingsView(app: app, throttleManager: throttleManager)
                case .presets:
                    PresetsView(app: app, throttleManager: throttleManager)
                case .traffic:
                    TrafficChartView(app: app, monitor: trafficMonitor)
                case .faults:
                    FaultInjectionView(injector: faultInjector)
                case .scenarios:
                    ScenariosView(app: app, engine: scenarioEngine)
                case .capture:
                    PacketCaptureView(app: app, captureManager: packetCapture)
                case .http:
                    HTTPInspectorView(app: app, inspector: httpInspector)
                case .profiles:
                    ProfilesView(app: app, throttleManager: throttleManager, profileManager: profileManager)
                case .report:
                    ReportExportView(
                        app: app, throttleManager: throttleManager,
                        trafficMonitor: trafficMonitor,
                        packetCapture: packetCapture,
                        faultInjector: faultInjector
                    )
                case .proxy:
                    ProxyView(proxyServer: proxyServer, throttleManager: throttleManager)
                case .settings:
                    SettingsView(webhookManager: webhookManager, serverManager: serverManager)
                case .log:
                    LogView(throttleManager: throttleManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("选择一个应用", systemImage: "app.dashed")
        } description: {
            Text("从左侧列表中选择一个正在运行的应用来设置网络限速")
        } actions: {
            Button("刷新进程列表") { processManager.refresh() }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Manual Settings

struct ManualSettingsView: View {
    let app: AppProcess
    @ObservedObject var throttleManager: ThrottleManager
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    @State private var downloadSpeed: String = ""
    @State private var uploadSpeed: String = ""
    @State private var latencyMs: Double = 0
    @State private var packetLoss: Double = 0
    @State private var speedUnit: SpeedUnit = .mbps

    enum SpeedUnit: String, CaseIterable {
        case kbps = "Kbps", mbps = "Mbps", gbps = "Gbps"
        var multiplier: Int {
            switch self { case .kbps: return 1; case .mbps: return 1000; case .gbps: return 1000000 }
        }
    }

    var body: some View {
        let theme = themeManager.currentTheme
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Current limits if throttled
                if let config = throttleManager.currentConfig(pid: app.pid) {
                    currentLimitsView(config: config)
                }

                // Speed section
                GroupBox("速度限制") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("单位").frame(width: 50, alignment: .trailing)
                            Picker("", selection: $speedUnit) {
                                ForEach(SpeedUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.frame(width: 100)
                            Spacer()
                        }
                        HStack {
                            Text("下载").frame(width: 50, alignment: .trailing)
                            TextField("不限", text: $downloadSpeed)
                                .textFieldStyle(.roundedBorder).frame(width: 120)
                            Text(speedUnit.rawValue).foregroundStyle(theme.textSecondary)
                            Spacer()
                        }
                        HStack {
                            Text("上传").frame(width: 50, alignment: .trailing)
                            TextField("不限", text: $uploadSpeed)
                                .textFieldStyle(.roundedBorder).frame(width: 120)
                            Text(speedUnit.rawValue).foregroundStyle(theme.textSecondary)
                            Spacer()
                        }
                    }.padding(.vertical, 6)
                }

                // Latency section
                GroupBox("延迟注入") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("延迟: \(Int(latencyMs)) ms")
                                .font(.body.monospacedDigit())
                            Spacer()
                            Text(latencyDesc).font(.caption).foregroundStyle(theme.textSecondary)
                        }
                        Slider(value: $latencyMs, in: 0...5000, step: 50)
                            .tint(latencyMs > 1000 ? theme.error : latencyMs > 300 ? theme.warning : theme.accent)
                        HStack {
                            Text("0ms").font(.caption2).foregroundStyle(theme.textTertiary)
                            Spacer()
                            Text("5000ms").font(.caption2).foregroundStyle(theme.textTertiary)
                        }
                    }.padding(.vertical, 6)
                }

                // Packet loss section
                GroupBox("丢包模拟") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("丢包率: \(String(format: "%.1f", packetLoss * 100))%")
                                .font(.body.monospacedDigit())
                            Spacer()
                            Text(lossDesc).font(.caption).foregroundStyle(theme.textSecondary)
                        }
                        Slider(value: $packetLoss, in: 0...0.5, step: 0.01)
                            .tint(packetLoss > 0.2 ? theme.error : packetLoss > 0.05 ? theme.warning : theme.accent)
                        HStack {
                            Text("0%").font(.caption2).foregroundStyle(theme.textTertiary)
                            Spacer()
                            Text("50%").font(.caption2).foregroundStyle(theme.textTertiary)
                        }
                    }.padding(.vertical, 6)
                }

                // Apply button
                HStack {
                    Button {
                        let config = buildConfig()
                        throttleManager.applyThrottle(app: app, config: config)
                    } label: {
                        Label("应用限速", systemImage: "bolt.shield.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .keyboardShortcut(.return, modifiers: .command)

                    Button {
                        resetForm()
                    } label: {
                        Text("重置")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
    }

    private func buildConfig() -> ThrottleConfig {
        let downKbps = Int(Double(downloadSpeed) ?? 0) * speedUnit.multiplier
        let upKbps = Int(Double(uploadSpeed) ?? 0) * speedUnit.multiplier
        return ThrottleConfig(
            downloadKbps: downKbps,
            uploadKbps: upKbps,
            latencyMs: Int(latencyMs),
            packetLoss: packetLoss
        )
    }

    private func resetForm() {
        downloadSpeed = ""
        uploadSpeed = ""
        latencyMs = 0
        packetLoss = 0
    }

    private var latencyDesc: String {
        if latencyMs == 0 { return "无延迟" }
        if latencyMs <= 100 { return "轻微 (类似近距离服务器)" }
        if latencyMs <= 300 { return "中等 (类似移动网络)" }
        if latencyMs <= 1000 { return "较高 (类似弱信号)" }
        return "极高 (类似断网前兆)"
    }

    private var lossDesc: String {
        if packetLoss == 0 { return "无丢包" }
        if packetLoss <= 0.02 { return "轻微 (WiFi 干扰)" }
        if packetLoss <= 0.05 { return "中等 (移动网络)" }
        if packetLoss <= 0.15 { return "较重 (弱信号)" }
        return "严重 (接近断连)"
    }

    private func currentLimitsView(config: ThrottleConfig) -> some View {
        GroupBox("当前限速") {
            HStack(spacing: 16) {
                if config.downloadKbps > 0 {
                    Label(throttleManager.formatSpeed(kbps: config.downloadKbps), systemImage: "arrow.down.circle.fill")
                        .font(.caption).foregroundStyle(themeManager.currentTheme.chartDownload)
                }
                if config.uploadKbps > 0 {
                    Label(throttleManager.formatSpeed(kbps: config.uploadKbps), systemImage: "arrow.up.circle.fill")
                        .font(.caption).foregroundStyle(themeManager.currentTheme.chartUpload)
                }
                if config.latencyMs > 0 {
                    Label("\(config.latencyMs)ms", systemImage: "clock.fill")
                        .font(.caption).foregroundStyle(theme.warning)
                }
                if config.packetLoss > 0 {
                    Label("\(Int(config.packetLoss * 100))%", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(theme.error)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Presets View

struct PresetsView: View {
    let app: AppProcess
    @ObservedObject var throttleManager: ThrottleManager
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.currentTheme
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(NetworkProfile.Category.allCases, id: \.self) { category in
                    let profiles = NetworkProfile.presets.filter { $0.category == category }
                    if !profiles.isEmpty {
                        Text(category.rawValue)
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        ForEach(profiles) { profile in
                            Button {
                                throttleManager.applyProfile(app: app, profile: profile)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: profile.icon)
                                        .font(.title3)
                                        .frame(width: 28)
                                        .foregroundStyle(theme.accent)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name).font(.body.bold())
                                        Text(profile.description)
                                            .font(.caption)
                                            .foregroundStyle(theme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()

                                    Image(systemName: "bolt.circle.fill")
                                        .foregroundStyle(theme.accent)
                                        .font(.title3)
                                }
                                .padding(10)
                                .glassCard(theme)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Scenarios View

struct ScenariosView: View {
    let app: AppProcess
    @ObservedObject var engine: ScenarioEngine
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    @State private var selectedScenario: TestScenario?

    var body: some View {
        let theme = themeManager.currentTheme
        VStack(spacing: 0) {
            if engine.isRunning {
                runningBanner
                Divider()
            }

            List(TestScenario.builtIn, selection: $selectedScenario) { scenario in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(scenario.name).font(.body.bold())
                        Spacer()
                        Text(scenario.loopCount == 0 ? "无限循环" : "循环 \(scenario.loopCount) 次")
                            .font(.caption).foregroundStyle(theme.textSecondary)
                    }
                    Text("\(scenario.steps.count) 步 · 总计 \(totalDuration(scenario))s")
                        .font(.caption).foregroundStyle(theme.textSecondary)

                    HStack(spacing: 4) {
                        ForEach(scenario.steps) { step in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForStep(step))
                                .frame(height: 4)
                        }
                    }
                }
                .padding(.vertical, 4)
                .tag(scenario)
            }
            .listStyle(.inset)

            if let scenario = selectedScenario {
                Divider()
                VStack(spacing: 8) {
                    // Step preview
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(scenario.steps) { step in
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(colorForStep(step))
                                        .frame(width: max(30, CGFloat(step.durationSeconds) * 8), height: 24)
                                    Text(step.name).font(.system(size: 8)).lineLimit(1)
                                    Text("\(step.durationSeconds)s").font(.system(size: 8)).foregroundStyle(theme.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    HStack {
                        if engine.isRunning {
                            Button { engine.stop() } label: {
                                Label("停止", systemImage: "stop.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(theme.error)
                        } else {
                            Button { engine.start(scenario: scenario, app: app) } label: {
                                Label("开始运行", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.success)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var runningBanner: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在运行: \(engine.currentScenarioName)").font(.caption.bold())
                Text("步骤 \(engine.currentStepIndex)/\(engine.totalSteps): \(engine.currentStepName) · 剩余 \(engine.remainingSeconds)s")
                    .font(.caption).foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Button("停止") { engine.stop() }
                .font(.caption).buttonStyle(.bordered).tint(theme.error)
        }
        .padding(10)
        .background(theme.success.opacity(0.1))
    }

    private func totalDuration(_ scenario: TestScenario) -> Int {
        scenario.steps.reduce(0) { $0 + $1.durationSeconds } * max(1, scenario.loopCount)
    }

    private func colorForStep(_ step: ScenarioStep) -> Color {
        let t = themeManager.currentTheme
        let c = step.config
        if c.downloadKbps <= 10 || c.packetLoss > 0.3 { return t.error }
        if c.packetLoss > 0.1 || c.latencyMs > 500 { return t.warning }
        if c.latencyMs > 0 || c.packetLoss > 0 || c.downloadKbps > 0 { return t.severityLow }
        return t.success
    }
}

// MARK: - Profiles View

struct ProfilesView: View {
    let app: AppProcess
    @ObservedObject var throttleManager: ThrottleManager
    @ObservedObject var profileManager: ProfileManager
    @EnvironmentObject var themeManager: ThemeManager

    @State private var showSaveSheet = false
    @State private var newProfileName = ""

    var body: some View {
        let theme = themeManager.currentTheme
        VStack(spacing: 0) {
            // Save current config button
            HStack {
                Button {
                    showSaveSheet = true
                } label: {
                    Label("保存当前配置", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(throttleManager.currentConfig(pid: app.pid) == nil)

                Spacer()

                Menu {
                    Button("导入配置文件...") { importProfile() }
                    if !profileManager.profiles.isEmpty {
                        Button("导出全部...") { exportProfiles() }
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 80)
            }
            .padding(10)

            Divider()

            if profileManager.profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.largeTitle).foregroundStyle(theme.textTertiary)
                    Text("暂无保存的配置").font(.caption).foregroundStyle(theme.textSecondary)
                    Text("应用限速后，可保存配置供复用").font(.caption2).foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(profileManager.profiles) { profile in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(.body.bold())
                                HStack(spacing: 8) {
                                    if profile.config.downloadKbps > 0 {
                                        Text("↓\(throttleManager.formatSpeed(kbps: profile.config.downloadKbps))")
                                            .font(.caption2)
                                    }
                                    if profile.config.uploadKbps > 0 {
                                        Text("↑\(throttleManager.formatSpeed(kbps: profile.config.uploadKbps))")
                                            .font(.caption2)
                                    }
                                    if profile.config.latencyMs > 0 {
                                        Text("\(profile.config.latencyMs)ms").font(.caption2)
                                    }
                                    if profile.config.packetLoss > 0 {
                                        Text("丢包\(Int(profile.config.packetLoss*100))%").font(.caption2)
                                    }
                                }
                                .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Button("应用") {
                                throttleManager.applyThrottle(app: app, config: profile.config)
                            }
                            .font(.caption).buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            profileManager.delete(profile: profileManager.profiles[index])
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            VStack(spacing: 16) {
                Text("保存测试配置").font(.headline)
                TextField("配置名称", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("取消") { showSaveSheet = false }
                    Spacer()
                    Button("保存") {
                        if let config = throttleManager.currentConfig(pid: app.pid) {
                            profileManager.save(name: newProfileName, config: config)
                        }
                        newProfileName = ""
                        showSaveSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newProfileName.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            profileManager.importFrom(url: url)
        }
    }

    private func exportProfiles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AppThrottler_Profiles.json"
        if panel.runModal() == .OK, let url = panel.url {
            profileManager.export(to: url)
        }
    }
}

// MARK: - Log View

struct LogView: View {
    @ObservedObject var throttleManager: ThrottleManager
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.currentTheme
        VStack(spacing: 0) {
            HStack {
                Text("操作记录 (\(throttleManager.logEntries.count))")
                    .font(.caption).foregroundStyle(theme.textSecondary)
                Spacer()
                Button("清空") { throttleManager.clearLog() }
                    .font(.caption).buttonStyle(.borderless)
            }
            .padding(10)

            Divider()

            if throttleManager.logEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(theme.textTertiary)
                    Text("暂无操作记录").font(.caption).foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(throttleManager.logEntries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.timeString)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 60, alignment: .leading)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(entry.appName) · \(entry.action)")
                                .font(.caption.bold())
                            if !entry.detail.isEmpty {
                                Text(entry.detail)
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Traffic Chart View

struct TrafficChartView: View {
    let app: AppProcess
    @ObservedObject var monitor: TrafficMonitor
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        VStack(spacing: 0) {
            // Live rate banner
            if monitor.isMonitoring {
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(theme.chartDownload)
                        Text(monitor.formattedRateIn)
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(theme.chartDownload)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(theme.chartUpload)
                        Text(monitor.formattedRateOut)
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(theme.chartUpload)
                    }
                    Spacer()
                    Image(systemName: "circle.fill")
                        .foregroundStyle(theme.success)
                        .font(.caption2)
                        .symbolEffect(.pulse, isActive: true)
                    Text("监控中")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.success.opacity(0.06))

                Divider()
            }

            // Chart area
            if monitor.history.isEmpty {
                ContentUnavailableView {
                    Label("暂无流量数据", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text(monitor.isMonitoring ? "等待数据采样..." : "点击下方按钮开始监控 \(app.name) 的网络流量")
                } actions: {
                    Button {
                        monitor.startMonitoring(pid: app.pid)
                    } label: {
                        Label("开始监控", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.success)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Swift Charts area chart
                        if #available(macOS 14.0, *) {
                            ChartSection(samples: Array(monitor.history.suffix(120)), theme: theme)
                                .padding(.top, 12)
                        } else {
                            legacyChart
                        }

                        Divider()

                        // Stats grid
                        statsGrid
                    }
                    .padding(.horizontal, 16)
                }
            }

            Divider()

            // Bottom controls
            HStack {
                if monitor.isMonitoring {
                    Button { monitor.stopMonitoring() } label: {
                        Label("停止监控", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered).tint(theme.error)
                } else {
                    Button { monitor.startMonitoring(pid: app.pid) } label: {
                        Label("开始监控", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(theme.success)
                }
                Spacer()
                Text("\(monitor.history.count) 采样点")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(12)
        }
    }

    // Fallback for older macOS
    private var legacyChart: some View {
        let samples = Array(monitor.history.suffix(60))
        let maxRate = max(samples.map { max($0.bytesIn, $0.bytesOut) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("实时速率").font(.caption.bold())
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(samples.indices, id: \.self) { i in
                    let sample = samples[i]
                    VStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(theme.chartUpload.opacity(0.8))
                            .frame(width: 4, height: CGFloat(sample.bytesOut) / CGFloat(maxRate) * 100)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(theme.chartDownload.opacity(0.8))
                            .frame(width: 4, height: CGFloat(sample.bytesIn) / CGFloat(maxRate) * 100)
                    }
                }
            }
            .frame(height: 105)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCard("总下载", monitor.formattedTotalIn, "arrow.down.circle", theme.chartDownload)
            statCard("总上传", monitor.formattedTotalOut, "arrow.up.circle", theme.chartUpload)
            statCard("平均速率", monitor.formattedAvgIn, "gauge.medium", theme.info)
            statCard("峰值下载", monitor.formattedPeakIn, "bolt.circle", theme.warning)
            statCard("峰值上传", monitor.formattedPeakOut, "bolt.circle", theme.warning)
            statCard("采样数", "\(monitor.stats.sampleCount)", "number.circle", theme.textSecondary)
        }
    }

    private func statCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2).foregroundStyle(theme.textSecondary)
                .labelStyle(.iconOnly)
            Text(value)
                .font(.callout.monospacedDigit().bold())
            Text(title)
                .font(.caption2).foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.usesGlass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Swift Charts Section (macOS 14+)

@available(macOS 14.0, *)
struct ChartSection: View {
    let samples: [TrafficSample]
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("实时速率").font(.caption.bold()).foregroundStyle(theme.textSecondary)

            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    AreaMark(
                        x: .value("时间", sample.timestamp),
                        y: .value("下载", max(0, Double(sample.bytesIn)))
                    )
                    .foregroundStyle(theme.chartDownload.opacity(0.3).gradient)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("时间", sample.timestamp),
                        y: .value("下载", max(0, Double(sample.bytesIn)))
                    )
                    .foregroundStyle(theme.chartDownload)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("时间", sample.timestamp),
                        y: .value("上传", max(0, Double(sample.bytesOut)))
                    )
                    .foregroundStyle(theme.chartUpload.opacity(0.3).gradient)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("时间", sample.timestamp),
                        y: .value("上传", max(0, Double(sample.bytesOut)))
                    )
                    .foregroundStyle(theme.chartUpload)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(theme.divider)
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(formatRate(bytes))
                                .font(.caption2)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.hour().minute().second()))
                                .font(.caption2)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
            }
            .chartLegend(position: .top, spacing: 8) {
                HStack(spacing: 16) {
                    Label("下载", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.chartDownload)
                    Label("上传", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.chartUpload)
                }
            }
            .frame(height: 180)
            .chartBackground { chartProxy in
                theme.usesGlass ? Color.clear : theme.surface.opacity(0.3)
            }
        }
    }

    private func formatRate(_ bytes: Double) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1fM", bytes / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0fK", bytes / 1024) }
        return String(format: "%.0f", bytes)
    }
}

// MARK: - Fault Injection View

struct FaultInjectionView: View {
    @ObservedObject var injector: FaultInjector
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerView
                ForEach(FaultType.allCases) { fault in
                    FaultRow(fault: fault, isActive: injector.isActive(fault)) {
                        injector.toggle(fault: fault)
                    }
                }
                warningView
            }
        }
        .alert("操作结果", isPresented: $injector.showResult) {
            Button("好的") { injector.showResult = false }
        } message: { Text(injector.resultMessage) }
    }

    private var headerView: some View {
        HStack {
            Text("故障注入").font(.headline)
            Spacer()
            if !injector.activeFaults.isEmpty {
                Button("全部停用") { injector.deactivateAll() }
                    .font(.caption).buttonStyle(.bordered).tint(theme.error)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var warningView: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
            Text("故障注入会影响系统全局网络，请在测试环境中使用。停用后将恢复原始配置。")
                .font(.caption).foregroundStyle(theme.textSecondary)
        }
        .padding(12).background(theme.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
}

struct FaultRow: View {
    let fault: FaultType
    let isActive: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.currentTheme
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: fault.icon)
                    .font(.title2)
                    .foregroundStyle(isActive ? theme.textInverse : theme.error)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fault.rawValue).font(.body.bold())
                    Text(fault.description)
                        .font(.caption)
                        .foregroundStyle(isActive ? theme.textInverse.opacity(0.8) : theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? theme.textInverse : theme.textSecondary)
            }
            .padding(12)
            .background(isActive ? theme.error : theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

// MARK: - Report Export View

struct ReportExportView: View {
    let app: AppProcess
    @ObservedObject var throttleManager: ThrottleManager
    @ObservedObject var trafficMonitor: TrafficMonitor
    @ObservedObject var packetCapture: PacketCaptureManager
    @ObservedObject var faultInjector: FaultInjector
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    @State private var reportURL: URL?
    @State private var showExporter = false
    @State private var includeTraffic = true
    @State private var includeCapture = true
    @State private var includeFaults = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("测试报告").font(.headline)
                    .padding(.horizontal, 16).padding(.top, 12)

                // Options
                GroupBox("报告内容") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("流量统计", isOn: $includeTraffic)
                        Toggle("抓包摘要", isOn: $includeCapture)
                        Toggle("故障注入记录", isOn: $includeFaults)
                    }.padding(4)
                }
                .padding(.horizontal, 16)

                // Preview
                GroupBox("预览") {
                    VStack(alignment: .leading, spacing: 8) {
                        previewRow("应用", app.name)
                        previewRow("PID", "\(app.pid)")
                        if let config = throttleManager.currentConfig(pid: app.pid) {
                            previewRow("限速", describeConfig(config))
                        }
                        if trafficMonitor.stats.sampleCount > 0 {
                            previewRow("流量采样", "\(trafficMonitor.stats.sampleCount) 次")
                        }
                        previewRow("抓包包数", "\(packetCapture.packets.count)")
                        if !faultInjector.activeFaults.isEmpty {
                            previewRow("故障注入", faultInjector.activeFaults.map(\.rawValue).joined(separator: ", "))
                        }
                    }.padding(4)
                }
                .padding(.horizontal, 16)

                // Export buttons
                HStack {
                    Button {
                        let report = buildReport()
                        let url = ReportGenerator.saveReport(report)
                        reportURL = url
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("生成并打开报告", systemImage: "doc.text.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showExporter = true
                    } label: {
                        Label("另存为...", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .fileExporter(isPresented: $showExporter, document: HTMLDocument(buildReport().generateHTML()), contentType: .html, defaultFilename: "AppThrottler_Report") { _ in }
    }

    private func buildReport() -> TestReport {
        TestReport(
            appName: app.name, pid: app.pid,
            startTime: trafficMonitor.stats.startTime ?? Date(),
            endTime: Date(),
            throttleConfig: throttleManager.currentConfig(pid: app.pid),
            presetName: nil,
            trafficStats: includeTraffic ? trafficMonitor.stats : nil,
            capturePacketCount: includeCapture ? packetCapture.packets.count : 0,
            faultInjection: includeFaults ? faultInjector.activeFaults.map(\.rawValue) : [],
            scenarioSteps: nil
        )
    }

    private func describeConfig(_ c: ThrottleConfig) -> String {
        var parts: [String] = []
        if c.downloadKbps > 0 { parts.append("↓\(c.downloadKbps)Kbps") }
        if c.uploadKbps > 0 { parts.append("↑\(c.uploadKbps)Kbps") }
        if c.latencyMs > 0 { parts.append("\(c.latencyMs)ms") }
        if c.packetLoss > 0 { parts.append("\(Int(c.packetLoss*100))%丢包") }
        return parts.joined(separator: " ") 
    }

    private func previewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(theme.textSecondary).frame(width: 80, alignment: .trailing)
            Text(value).font(.caption)
            Spacer()
        }
    }
}

// Simple FileDocument for HTML export
import UniformTypeIdentifiers
struct HTMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }
    var content: String
    init(_ content: String) { self.content = content }
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else { content = "" }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var webhookManager: WebhookManager
    @ObservedObject var serverManager: ServerManager
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        let theme = themeManager.currentTheme
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置").font(.headline)
                    .padding(.horizontal, 16).padding(.top, 12)

                GroupBox("外观主题") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                        ForEach(ThemeOption.allCases) { option in
                            let isSelected = themeManager.option == option
                            Button { themeManager.select(option) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: option.icon)
                                        .font(.title2)
                                        .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                                    Text(option.name)
                                        .font(.caption)
                                        .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected ? theme.accent.opacity(0.12) : theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(4)
                }
                .padding(.horizontal, 16)

                GroupBox("远程控制服务器") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用 HTTP Server", isOn: Binding(
                            get: { serverManager.isRunning },
                            set: { if $0 { serverManager.start() } else { serverManager.stop() } }
                        ))

                        if serverManager.isRunning {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("地址").font(.caption2).foregroundStyle(theme.textSecondary)
                                    Text("http://localhost:\(serverManager.port)")
                                        .font(.caption.monospaced()).textSelection(.enabled)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("配对令牌").font(.caption2).foregroundStyle(theme.textSecondary)
                                    HStack(spacing: 4) {
                                        Text(serverManager.authToken)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(serverManager.authToken, forType: .string)
                                        } label: {
                                            Image(systemName: "doc.on.doc").font(.caption2)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("状态").font(.caption2).foregroundStyle(theme.textSecondary)
                                    HStack(spacing: 4) {
                                        Circle().fill(theme.success).frame(width: 6, height: 6)
                                        Text("运行中 · \(serverManager.connectedClients) 客户端")
                                            .font(.caption)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }

                        if let err = serverManager.serverError {
                            Text(err).font(.caption).foregroundStyle(theme.error)
                        }
                    }.padding(4)
                }
                .padding(.horizontal, 16)

                GroupBox("Webhook 通知") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用 Webhook", isOn: $webhookManager.enabled)
                        if webhookManager.enabled {
                            HStack {
                                Text("URL:")
                                TextField("https://example.com/webhook", text: $webhookManager.webhookURL)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Text("限速/故障注入等操作会 POST JSON 到此 URL")
                                .font(.caption).foregroundStyle(theme.textSecondary)
                            if webhookManager.sendCount > 0 {
                                HStack {
                                    Text("已发送 \(webhookManager.sendCount) 次")
                                    if let last = webhookManager.lastSentAt {
                                        Text("· 最近: \(last.formatted(date: .omitted, time: .standard))")
                                    }
                                }
                                .font(.caption).foregroundStyle(theme.textSecondary)
                            }
                        }
                    }.padding(4)
                }
                .padding(.horizontal, 16)

                GroupBox("外观主题") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                        ForEach(ThemeOption.allCases) { option in
                            let isSelected = themeManager.option == option
                            Button { themeManager.select(option) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: option.icon)
                                        .font(.title2)
                                        .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                                    Text(option.name)
                                        .font(.caption)
                                        .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected ? theme.accent.opacity(0.12) : theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(4)
                }
                .padding(.horizontal, 16)

                GroupBox("CLI 使用说明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("在终端中使用以下命令：")
                            .font(.caption).bold()
                        codeBlock("""
                        # 列出进程
                        AppThrottler list
                        # 限速（需 sudo）
                        sudo AppThrottler apply --pid 1234 --download 1000 --latency 200
                        # 抓包
                        sudo AppThrottler capture --pid 1234 --duration 30
                        # 清除所有
                        sudo AppThrottler remove-all
                        """)
                    }.padding(4)
                }
                .padding(.horizontal, 16)

                GroupBox("AppleScript") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("通过 AppleScript 控制限速：")
                            .font(.caption).bold()
                        codeBlock("""
                        tell application "AppThrottler"
                            -- 由外部脚本通过 CLI 控制
                        end tell
                        """)
                        Text("推荐使用 CLI 模式进行自动化集成")
                            .font(.caption).foregroundStyle(theme.textSecondary)
                    }.padding(4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Packet Capture View

struct PacketCaptureView: View {
    let app: AppProcess
    @ObservedObject var captureManager: PacketCaptureManager
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        let theme = themeManager.currentTheme
        VStack(spacing: 0) {
            // Controls bar
            HStack(spacing: 12) {
                if captureManager.isCapturing {
                    Button { captureManager.stopCapture() } label: {
                        Label("停止抓包", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.error)

                    // Live stats
                    HStack(spacing: 10) {
                        Label(captureManager.stats.formattedDuration, systemImage: "clock")
                        Label("\(captureManager.stats.totalPackets) 包", systemImage: "doc.text")
                        Label(captureManager.stats.formattedTotalBytes, systemImage: "arrow.up.arrow.down")
                        Label(captureManager.stats.formattedRate, systemImage: "speedometer")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                } else {
                    Button { captureManager.startCaptureWithPrivileges(app: app) } label: {
                        Label("开始抓包", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.success)
                }

                Spacer()

                if !captureManager.packets.isEmpty {
                    // Export button
                    Button {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.data]
                        panel.nameFieldStringValue = "\(app.name)_capture.pcap"
                        if panel.runModal() == .OK, let url = panel.url {
                            captureManager.exportPcap(to: url)
                        }
                    } label: {
                        Label("导出 pcap", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button { captureManager.packets = [] } label: {
                        Text("清空").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(10)

            // Filter bar
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(theme.textSecondary)
                TextField("过滤 (IP/端口/协议)...", text: $captureManager.filterText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !captureManager.filterText.isEmpty {
                    Button { captureManager.filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Divider()

            // Error display
            if let error = captureManager.captureError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
                    Text(error).font(.caption).foregroundStyle(theme.textSecondary)
                    Spacer()
                }
                .padding(10)
                .background(theme.warning.opacity(0.1))
            }

            // Stats bar
            if captureManager.isCapturing {
                HStack(spacing: 16) {
                    statBadge("TCP", count: captureManager.stats.tcpPackets, color: theme.protoTCP)
                    statBadge("UDP", count: captureManager.stats.udpPackets, color: theme.protoUDP)
                    statBadge("其他", count: captureManager.stats.otherPackets, color: theme.textTertiary)
                    Spacer()
                    Text("显示 \(captureManager.filteredPackets.count) / \(captureManager.packets.count)")
                        .font(.caption2).foregroundStyle(theme.textSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
            }

            Divider()

            // Packet list
            if captureManager.packets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle).foregroundStyle(theme.textTertiary)
                    Text(captureManager.isCapturing ? "等待数据包..." : "点击\"开始抓包\"捕获 \(app.name) 的网络流量")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Packet table
                List(captureManager.filteredPackets.suffix(2000)) { packet in
                    HStack(spacing: 6) {
                        Text(packet.timeString)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 75, alignment: .leading)

                        Text(packet.protocol_)
                            .font(.caption2.bold())
                            .foregroundStyle(protoColor(packet.protocol_))
                            .frame(width: 35, alignment: .center)
                            .padding(.horizontal, 3)
                            .background(protoColor(packet.protocol_).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text(packet.source)
                            .font(.caption.monospaced())
                            .frame(minWidth: 120, alignment: .leading)

                        Image(systemName: "arrow.right")
                            .font(.caption2).foregroundStyle(theme.textTertiary)

                        Text(packet.destination)
                            .font(.caption.monospaced())
                            .frame(minWidth: 120, alignment: .leading)

                        Text("\(packet.length)B")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 50, alignment: .trailing)

                        Text(packet.info)
                            .font(.caption2)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 1)
                }
                .listStyle(.plain)
            }
        }
    }

    private func statBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label): \(count)").font(.caption2.monospacedDigit())
        }
        .foregroundStyle(theme.textSecondary)
    }

    private func protoColor(_ proto: String) -> Color {
        let t = themeManager.currentTheme
        switch proto {
        case "TCP": return t.protoTCP
        case "UDP": return t.protoUDP
        case "ICMP": return t.protoICMP
        case "DNS": return t.protoDNS
        default: return t.textTertiary
        }
    }
}

// MARK: - App Row

struct AppRow: View {
    let app: AppProcess
    @ObservedObject var throttleManager: ThrottleManager
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.currentTheme
        Label {
            HStack(spacing: 6) {
                Text(app.name)
                    .lineLimit(1)
                Spacer()
                if throttleManager.isThrottled(pid: app.pid) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundStyle(theme.warning)
                        .font(.caption2)
                        .symbolEffect(.pulse, isActive: true)
                }
            }
        } icon: {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(theme.accent)
                    .frame(width: 20, height: 20)
            }
        }
    }
}

// MARK: - iPhone Proxy View

struct ProxyView: View {
    @ObservedObject var proxyServer: ProxyServer
    @ObservedObject var throttleManager: ThrottleManager
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    @State private var downloadSpeed: String = "1000"
    @State private var uploadSpeed: String = "500"
    @State private var latencyMs: Double = 200
    @State private var packetLoss: Double = 0.05

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Server control
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用 iPhone 代理", isOn: Binding(
                            get: { proxyServer.isRunning },
                            set: { if $0 { proxyServer.start() } else { proxyServer.stop() } }
                        ))
                        .toggleStyle(.switch)

                        if proxyServer.isRunning {
                            HStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("代理地址").font(.caption2).foregroundStyle(theme.textSecondary)
                                    Text("\(proxyServer.localIPAddress()):\(proxyServer.port)")
                                        .font(.body.monospaced().bold())
                                        .textSelection(.enabled)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("状态").font(.caption2).foregroundStyle(theme.textSecondary)
                                    HStack(spacing: 4) {
                                        Circle().fill(theme.success).frame(width: 8, height: 8)
                                        Text("运行中")
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("已连接设备").font(.caption2).foregroundStyle(theme.textSecondary)
                                    Text("\(proxyServer.connectedDevices)")
                                        .font(.body.monospacedDigit().bold())
                                }
                            }
                            .padding(.top, 4)
                        }
                    }.padding(4)
                } label: {
                    Label("代理服务器", systemImage: "wifi.router")
                }
                .padding(.horizontal, 16)

                // Setup instructions
                if proxyServer.isRunning {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            instructionStep(1, "打开 iPhone → 设置 → WiFi")
                            instructionStep(2, "点击当前网络旁的 ⓘ")
                            instructionStep(3, "配置代理 → 手动")
                            instructionStep(4, "服务器填入: \(proxyServer.localIPAddress())")
                            instructionStep(5, "端口填入: \(proxyServer.port)")
                            instructionStep(6, "点击存储")
                        }.padding(4)
                    } label: {
                        Label("iPhone 设置步骤", systemImage: "iphone")
                    }
                    .padding(.horizontal, 16)
                }

                // Throttle settings
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("下载限速").frame(width: 70, alignment: .trailing)
                            TextField("1000", text: $downloadSpeed)
                                .textFieldStyle(.roundedBorder).frame(width: 100)
                            Text("Kbps").foregroundStyle(theme.textSecondary)
                            Spacer()
                        }
                        HStack {
                            Text("上传限速").frame(width: 70, alignment: .trailing)
                            TextField("500", text: $uploadSpeed)
                                .textFieldStyle(.roundedBorder).frame(width: 100)
                            Text("Kbps").foregroundStyle(theme.textSecondary)
                            Spacer()
                        }
                        HStack {
                            Text("延迟").frame(width: 70, alignment: .trailing)
                            Slider(value: $latencyMs, in: 0...2000, step: 50)
                            Text("\(Int(latencyMs))ms")
                                .font(.caption.monospacedDigit())
                                .frame(width: 50)
                        }
                        HStack {
                            Text("丢包率").frame(width: 70, alignment: .trailing)
                            Slider(value: $packetLoss, in: 0...0.5, step: 0.01)
                            Text("\(String(format: "%.0f", packetLoss * 100))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 40)
                        }
                    }.padding(4)
                } label: {
                    Label("限速配置", systemImage: "speedometer")
                }
                .padding(.horizontal, 16)

                // Connected devices
                let devices = proxyServer.connectedDeviceList
                if !devices.isEmpty {
                    GroupBox {
                        ForEach(devices) { device in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundStyle(theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).font(.body)
                                    Text("\(device.connectionCount) 连接")
                                        .font(.caption).foregroundStyle(theme.textSecondary)
                                }
                                Spacer()
                                if device.isThrottled {
                                    Label("已限速", systemImage: "bolt.shield.fill")
                                        .font(.caption).foregroundStyle(theme.warning)
                                    Button("解除") {
                                        proxyServer.unthrottleDevice(device.id)
                                    }
                                    .font(.caption).buttonStyle(.borderless)
                                } else {
                                    Button("限速此设备") {
                                        let down = Int(downloadSpeed) ?? 1000
                                        let up = Int(uploadSpeed) ?? 500
                                        proxyServer.throttleDevice(
                                            device.id,
                                            downloadKbps: down, uploadKbps: up,
                                            latencyMs: Int(latencyMs), packetLoss: packetLoss
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(theme.accent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        Label("已连接设备 (\(devices.count))", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .padding(.horizontal, 16)
                }

                // Traffic log
                if !proxyServer.trafficLog.isEmpty {
                    GroupBox {
                        ForEach(proxyServer.trafficLog.prefix(20)) { entry in
                            HStack(spacing: 6) {
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(theme.textTertiary)
                                Text(entry.deviceIP)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(theme.accent)
                                Text(entry.method)
                                    .font(.caption2.bold())
                                    .foregroundStyle(theme.info)
                                Text(entry.host)
                                    .font(.caption).lineLimit(1)
                                Spacer()
                                if entry.isThrottled {
                                    Image(systemName: "bolt.fill")
                                        .font(.caption2).foregroundStyle(theme.warning)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    } label: {
                        Label("流量日志 (\(proxyServer.trafficLog.count))", systemImage: "list.bullet")
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func instructionStep(_ num: Int, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text("\(num)")
                .font(.caption2.bold())
                .frame(width: 20, height: 20)
                .background(theme.accent.opacity(0.15))
                .clipShape(Circle())
            Text(text).font(.caption)
        }
    }
}
