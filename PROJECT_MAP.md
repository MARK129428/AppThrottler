# AppThrottler 项目地图

> 下次开发时的快速导航指南。先读这个文件，再动手改代码。

## 快速定位

```
要改什么 → 看哪个文件
─────────────────────────────────────────────────
限速逻辑           → ThrottleManager.swift
故障注入           → FaultInjector.swift
抓包               → PacketCaptureManager.swift
HTTP 调试          → HTTPInspector.swift
流量监控           → TrafficMonitor.swift
场景编排           → ScenarioEngine.swift
进程列表           → ProcessManager.swift
主题/颜色          → Theme.swift
Toast 通知         → ToastView.swift
CLI 命令           → CLIRunner.swift
REST API Server    → ServerManager.swift (半成品，handler 是空壳)
iPhone 代理        → ProxyServer.swift
测试配置           → ProfileManager.swift
测试报告           → ReportGenerator.swift
Webhook/AppScript  → Integrations.swift
主界面 (11 Tab)    → ContentView.swift (~1850 行)
HTTP 调试 UI       → HTTPInspectorView.swift
App 入口           → AppThrottlerApp.swift
```

## 文件清单 (23 个源文件)

```
AppThrottler/
├── AppThrottlerApp.swift          # 入口：CLI/GUI 双模式分发
│   ├── CLI 模式 → CLIRunner.run() + exit(0)
│   └── GUI 模式 → NSApplication + AppThrottlerDelegate
│       └── applicationWillTerminate → 清理所有 PF/dnctl/hosts
│
├── ContentView.swift              # 主界面（~1850 行）
│   ├── ContentView                # NavigationSplitView + 11 Tab
│   ├── ManualSettingsView         # 手动限速设置
│   ├── PresetsView                # 10 个网络预设
│   ├── TrafficChartView           # Swift Charts 流量图
│   ├── FaultInjectionView         # 故障注入面板
│   ├── FaultRow                   # 单个故障行
│   ├── ScenariosView              # 场景编排
│   ├── PacketCaptureView          # 抓包面板
│   ├── ProfilesView               # 测试配置管理
│   ├── ReportExportView           # 测试报告导出
│   ├── SettingsView               # 设置（主题+服务器+Webhook）
│   ├── LogView                    # 操作日志
│   ├── ProxyView                  # iPhone 代理限速
│   ├── ChartSection               # Swift Charts 图表组件
│   └── AppRow                     # 侧边栏进程行
│
├── HTTPInspectorView.swift        # HTTP 调试 UI
│   ├── HTTPInspectorView          # 主视图
│   └── HTTPTransactionRow         # 请求行
│
├── Theme.swift                    # 主题设计系统
│   ├── ThemeOption (enum)         # 4 个主题选项
│   ├── AppTheme (struct)          # 50+ 语义色属性
│   ├── ThemeManager (@MainActor)  # 主题管理 + UserDefaults
│   ├── GlassCardModifier          # 毛玻璃卡片
│   └── GlassPanelModifier         # 毛玻璃面板
│
├── ToastView.swift                # 通知系统
│   ├── ToastManager               # Toast 管理
│   ├── ToastOverlay               # 覆盖层
│   ├── ToastView                  # 单个 Toast
│   ├── ThrottleLoadingView        # 加载态
│   ├── ActiveBadge                # 活跃指示器
│   └── HoverCardModifier          # Hover 卡片效果
│
├── ThrottleManager.swift          # 限速核心
│   ├── PrivilegedExecutor (actor) # 异步特权执行器
│   └── ThrottleManager            # UID 匹配限速
│
├── FaultInjector.swift            # 故障注入
├── PacketCaptureManager.swift     # tcpdump 抓包
├── HTTPInspector.swift            # HTTP 请求解析
├── TrafficMonitor.swift           # nettop 流量监控
├── ScenarioEngine.swift           # 场景编排引擎
├── ProcessManager.swift           # 进程枚举
├── NetworkProfile.swift           # 预设模板 + ThrottleConfig
├── ProfileManager.swift           # 测试配置持久化
├── ReportGenerator.swift          # HTML 报告生成
├── Integrations.swift             # Webhook + AppleScriptBridge
├── CLIRunner.swift                # CLI 模式（无 @MainActor）
├── ServerManager.swift            # REST API（空壳 handler）
├── ProxyServer.swift              # HTTP CONNECT 代理
├── Info.plist                     # App Bundle 配置
└── Resources/AppIcon.svg          # 图标源文件
```

## 架构模式

### 所有 Manager 遵循同一模式
```swift
@MainActor
class XXXManager: ObservableObject {
    @Published var someState: SomeType  // UI 绑定
    private var internalState: SomeType  // 内部状态
    private let executor = PrivilegedExecutor.shared  // 异步特权

    func doSomething() async {  // 异步，不阻塞 UI
        let result = await executor.run("shell command", prompt: "...")
        if result.success { /* 更新状态 */ }
    }
}
```

### 特权操作统一流程
```
UI 按钮 → Task { await manager.method() }
         → manager 调用 PrivilegedExecutor.run()
         → Executor 在后台线程执行 NSAppleScript
         → 返回结果到 @MainActor
         → 更新 @Published 状态
         → SwiftUI 自动刷新
```

### PF 规则结构
```
appthrottler              ← 主锚点（限速规则，UID 匹配）
appthrottler/fault        ← 子锚点（故障注入）
appthrottler/proxy        ← 子锚点（iPhone 代理限速）
```

### 管道编号分配
```
ThrottleManager: 100-499（每次调用 +1）
ProxyServer:     500-899（按设备 IP hash）
CLIRunner:       100 + PID % 900（固定公式）
```

## 关键技术决策

| 决策 | 选型 | 原因 |
|------|------|------|
| 限速匹配 | UID 而非端口 | 端口是临时的，UID 跨连接稳定 |
| 特权执行 | PrivilegedExecutor actor | NSAppleScript 不能在 @MainActor 上同步调用 |
| 主题 | 4 套 AppTheme + EnvironmentObject | 比 color assets 更灵活 |
| 毛玻璃 | Material + usesGlass 标志 | 3 个自定义主题用 glass，System 跟随原生 |
| 进程列表 | NSWorkspace (GUI) / ps (CLI) | NSWorkspace 在 CLI 模式不可用 |
| 通知 | Toast 替代 Alert | Alert 阻塞交互，Toast 非阻塞 |
| HTTP 解析 | tcpdump -A + NSRegularExpression | 无需代理服务器即可查看 HTTP |

## 已知问题 / TODO

### ServerManager 是空壳
`ServerManager.swift` 的 handler 全部返回硬编码空数据。需要：
1. 注入 ThrottleManager, ProcessManager 等引用
2. 让 handler 调用真实 Manager 方法
3. WebSocket 推送真实事件

### iOS 遥控 App 未实现
Phase 3 计划在 `~/Desktop/AppThrottler-iOS/` 创建 iOS 项目，当前只完成设计。

### ContentView.swift 过大 (~1850 行)
所有 Tab 的 View 都在同一个文件里。建议拆分为：
```
Views/
├── ManualSettingsView.swift
├── PresetsView.swift
├── TrafficChartView.swift
├── FaultInjectionView.swift
├── ...
```

### CLIRunner 不支持 async
CLIRunner 是同步的，直接调用 `Process.waitUntilExit()`。因为 CLI 模式没有 UI，这可以接受，但如果要支持长时间操作需要改造。

## 构建与测试

```bash
# 构建
./build.sh

# 运行 GUI
open build/AppThrottler.app

# 运行 CLI
./cli list
./cli help

# 检查编译警告
./build.sh 2>&1 | grep "warning:"

# 搜索残留硬编码颜色
grep -rn "Color\.\(blue\|red\|green\)" AppThrottler/*.swift | grep -v Theme.swift

# 推送到 GitHub
git add -A && git commit -m "..." && git push
```

## 数据流图

```
┌─────────────┐    ┌─────────────────┐    ┌──────────────┐
│ ContentView │───→│ ThrottleManager │───→│PrivilegedExec│
│ (SwiftUI)   │←───│ (@MainActor)    │←───│ (actor/bkg)  │
└──────┬──────┘    └────────┬────────┘    └──────┬───────┘
       │                    │                     │
       │            ┌───────▼───────┐    ┌───────▼───────┐
       │            │  dnctl pipe   │    │ NSAppleScript │
       │            │  pfctl anchor │    │ (sudo auth)   │
       │            └───────────────┘    └───────────────┘
       │
       ├──→ FaultInjector → pfctl/fault anchor + /etc/hosts
       ├──→ PacketCapture → tcpdump subprocess
       ├──→ TrafficMonitor → nettop subprocess
       ├──→ HTTPInspector → tcpdump -A + regex parse
       ├──→ ScenarioEngine → 循环调用 ThrottleManager
       ├──→ ProxyServer → NWListener + HTTP CONNECT
       └──→ ServerManager → (空壳，待接入)
```

## Git 提交规范

```
feat: 新功能
fix: 修复
refactor: 重构
style: UI/主题调整
docs: 文档
perf: 性能优化
```
