# CLAUDE.md — AppThrottler AI 开发指南

本文件帮助 AI agent 快速理解项目结构并进行渐进开发。请在每次修改前阅读。

## 项目概览

AppThrottler 是一个 macOS 桌面网络测试工具，用于对指定应用进行限速、故障注入和抓包。
同时提供 GUI（SwiftUI）和 CLI 两种使用方式。

**核心技术栈：**
- Swift 5.9+ / SwiftUI / AppKit
- macOS 14.0+ (Sonoma)
- `dnctl` (dummynet) — 流量管道，控制带宽/延迟/丢包
- `pfctl` (Packet Filter) — 将进程流量重定向到 dummynet 管道
- `lsof` — 发现进程的网络连接（端口）
- `tcpdump` — 数据包捕获
- `NSAppleScript` — 弹出管理员密码对话框获取 sudo 权限

## 目录结构

```
AppThrottler/
├── AppThrottlerApp.swift        # 入口：CLI/GUI 双模式分发
├── ContentView.swift            # 主界面：所有 Tab 视图定义
├── ProcessManager.swift         # 进程枚举（NSWorkspace + sysctl）
├── ThrottleManager.swift        # 核心限速逻辑（dnctl/pfctl）
├── NetworkProfile.swift         # 预设模板数据模型（2G~5G 等）
├── ScenarioEngine.swift         # 场景编排引擎（时间线自动切换）
├── ProfileManager.swift         # 测试配置保存/加载（JSON）
├── PacketCaptureManager.swift   # 抓包管理（tcpdump 子进程）
├── HTTPInspector.swift          # HTTP 调试（请求解析/重放/Mock/cURL/Diff/会话）
├── HTTPInspectorView.swift      # HTTP 调试 UI
├── TrafficMonitor.swift         # 实时流量监控（nettop）
├── FaultInjector.swift          # 故障注入（DNS/TCP/SSL）
├── ReportGenerator.swift        # 测试报告生成（HTML）
├── Integrations.swift           # Webhook + AppleScript 桥接
├── CLIRunner.swift              # CLI 模式（纯命令行，不依赖 NSWorkspace）
├── Info.plist                   # App Bundle 配置
└── Resources/AppIcon.svg        # 应用图标源文件

build.sh                         # 一键构建脚本
Makefile                         # make build/run/clean
project.yml                      # xcodegen 配置（可选）
cli                              # CLI 快捷入口脚本
AppIcon.icns                     # macOS 应用图标
```

## 关键架构决策

### 1. 双模式入口 (AppThrottlerApp.swift)
```swift
@main
struct AppThrottlerEntry {
    static func main() {
        if CommandLine.arguments.count > 1 {
            // CLI 模式：直接执行命令，不启动 GUI
            let runner = CLIRunner()
            runner.run()
            exit(0)
        } else {
            // GUI 模式：启动 NSApplication + SwiftUI
            NSApplication.shared.delegate = AppThrottlerDelegate()
            NSApplication.shared.run()
        }
    }
}
```

### 2. 限速原理 (ThrottleManager.swift)
限速通过三层 macOS 系统命令实现：
1. `dnctl pipe N config bw X delay Y plr Z` — 创建流量管道（带宽/延迟/丢包）
2. `pfctl -a appthrottler -f -` — 加载 PF 锚点规则
3. PF 规则将特定端口流量导向 dnctl 管道

**关键点：** PF 规则匹配的是端口而非进程名，所以需要先用 `lsof` 获取进程的端口列表。

### 3. 权限获取 (ThrottleManager.swift)
所有需要 root 权限的操作通过 `NSAppleScript` 的 `with administrator privileges` 实现：
```swift
do shell script "..." with administrator privileges with prompt "..."
```
这会弹出 macOS 原生密码对话框。

### 4. CLI vs GUI 的 ProcessManager 差异
- **GUI** (`ProcessManager.swift`)：使用 `NSWorkspace.shared.runningApplications` 获取 GUI 应用（带图标、bundleId）
- **CLI** (`CLIRunner.swift`)：使用 `/bin/ps -axo pid,comm` 获取所有进程（不依赖 NSApplication）

### 5. Tab 界面 (ContentView.swift)
右侧面板使用可滚动的胶囊按钮 Tab 栏（非 segmented Picker），因为有 10+ 个 Tab。

## 编码规范

- **文件组织**：每个 Manager/Engine 一个文件，视图定义在 ContentView.swift 中
- **命名**：`@MainActor` 类用 `ObservableObject`，视图用 `struct XXXView: View`
- **权限操作**：统一通过 `runPrivileged()` 方法调用 NSAppleScript
- **进程通信**：统一通过 `shell()` / `exec()` 方法调用外部命令
- **错误处理**：通过 `@Published var resultMessage` + `.alert()` 展示给用户
- **不使用注释**：除非有非直觉的约束或 workaround

## 添加新功能的步骤

1. **确定功能类型**：限速相关 → ThrottleManager | UI 面板 → ContentView 新 Tab | 新 Manager → 独立文件
2. **创建数据模型**（如需要）→ `NetworkProfile.swift` 风格的 struct
3. **实现核心逻辑** → 新建 `XXXManager.swift` 或在现有 Manager 中添加方法
4. **添加 UI** → 在 `ContentView.swift` 中添加新 View struct + 在 Tab 枚举中添加 case
5. **添加 CLI 支持** → 在 `CLIRunner.swift` 中添加命令处理
6. **更新构建脚本** → 在 `build.sh` 的 SOURCES 数组中添加新文件
7. **构建测试** → 运行 `./build.sh` 确保编译通过

## 常见陷阱

- **`sysctl` 类型**：`size` 参数用 `Int`（不是 `Int32`），macOS 的 `size_t` 映射为 `Int`
- **Swift Regex**：当前编译器不支持 `/pattern/` 字面量，用 `NSRegularExpression` 替代
- **`NSWorkspace`**：CLI 模式下不可用，必须用 `ps` 命令替代
- **PF 锚点**：`pfctl -a anchorname -f -` 需要先设置锚点再加载规则
- **Tab 数量**：超过 6 个时 segmented Picker 会被截断，改用 ScrollView 胶囊按钮
- **`@MainActor`**：CLI 模式下创建 `@MainActor` 对象可能死锁，CLIRunner 不用 `@MainActor`
- **Info.plist**：构建脚本生成实际值（非 `$(VARIABLE)`），Xcode 项目用 `$(VARIABLE)`

## 构建与运行

```bash
# 构建
./build.sh

# GUI 模式
open build/AppThrottler.app

# CLI 模式
./cli list
./cli apply --pid 1234 --download 1000 --latency 200
./cli capture --pid 1234 --duration 30
./cli remove-all

# 使用 xcodegen（可选）
brew install xcodegen && xcodegen generate
open AppThrottler.xcodeproj
```

## 测试清单

修改后请验证：
- [ ] `./build.sh` 编译通过（零 error，尽量零 warning）
- [ ] `./cli list` 能列出进程
- [ ] `./cli help` 显示帮助
- [ ] GUI 能正常启动并显示应用列表
- [ ] 选择应用后 Tab 切换正常
- [ ] 限速/解除限速功能正常（需管理员权限）
