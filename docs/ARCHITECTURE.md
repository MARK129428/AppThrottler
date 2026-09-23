# 架构文档

## 系统架构图

```
┌──────────────────────────────────────────────────────┐
│                   AppThrottlerApp                     │
│               (CLI/GUI 双模式入口)                      │
├────────────────┬─────────────────────────────────────┤
│                │                                     │
│   CLI 模式      │         GUI 模式                     │
│  CLIRunner     │    NSApplication + SwiftUI           │
│  (纯命令行)     │        ContentView                   │
│                │    ┌──────────────────────┐          │
│                │    │  10 个功能 Tab 面板     │          │
│                │    └──────────────────────┘          │
│                │                                     │
├────────────────┴─────────────────────────────────────┤
│                   核心业务层                            │
│  ┌──────────────┐ ┌──────────────┐ ┌───────────────┐ │
│  │ThrottleManager│ │FaultInjector │ │TrafficMonitor │ │
│  │  限速核心      │ │  故障注入     │ │  流量监控      │ │
│  └──────┬───────┘ └──────┬───────┘ └──────┬────────┘ │
│         │                │                │          │
│  ┌──────────────┐ ┌──────────────┐ ┌───────────────┐ │
│  │ScenarioEngine│ │PacketCapture │ │ReportGenerator│ │
│  │  场景编排      │ │  抓包管理     │ │  报告生成      │ │
│  └──────────────┘ └──────────────┘ └───────────────┘ │
│                                                      │
│  ┌──────────────┐ ┌──────────────┐ ┌───────────────┐ │
│  │ProfileManager│ │  Integrations│ │NetworkProfile │ │
│  │  配置管理      │ │  集成接口     │ │  预设模型      │ │
│  └──────────────┘ └──────────────┘ └───────────────┘ │
├──────────────────────────────────────────────────────┤
│                   macOS 系统层                         │
│                                                      │
│  dnctl (dummynet)    pfctl (Packet Filter)            │
│  ┌─────────────┐     ┌──────────────────┐            │
│  │ pipe N       │◄────│ anchor rules     │            │
│  │ bw/delay/plr │     │ port → pipe 映射  │            │
│  └─────────────┘     └──────────────────┘            │
│                                                      │
│  lsof              tcpdump           nettop           │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     │
│  │端口发现    │     │数据包捕获  │     │流量统计   │     │
│  └──────────┘     └──────────┘     └──────────┘     │
│                                                      │
│  NSAppleScript     /etc/hosts        /bin/ps          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     │
│  │sudo权限弹窗│     │DNS劫持   │     │进程列表   │     │
│  └──────────┘     └──────────┘     └──────────┘     │
└──────────────────────────────────────────────────────┘
```

## 数据流

### 限速流程
```
用户选择应用 + 设置参数
        │
        ▼
  lsof -p PID          ← 获取进程的网络端口列表
        │
        ▼
  dnctl pipe N config   ← 创建带宽/延迟/丢包管道
        │
        ▼
  pfctl anchor rules    ← 将端口流量导向管道
        │
        ▼
  进程流量被限速
```

### 故障注入流程
```
用户选择故障类型
        │
        ├── DNS 故障 → 修改 /etc/hosts + flushcache
        ├── TCP RST  → pfctl block return
        └── SSL 错误  → pfctl block port 443
```

### 抓包流程
```
用户选择应用 + 点击开始
        │
        ▼
  lsof -p PID          ← 获取端口列表
        │
        ▼
  tcpdump -i any       ← 启动抓包子进程
    port X or port Y
        │
        ▼
  实时解析输出 → CapturedPacket 列表
        │
        ▼
  -w file.pcap         ← 同时保存 pcap 文件
```

## 关键类关系

```
ContentView (SwiftUI)
    ├── ProcessManager        @StateObject
    ├── ThrottleManager       @StateObject
    ├── TrafficMonitor        @StateObject
    ├── FaultInjector         @StateObject
    ├── ScenarioEngine        @StateObject
    ├── PacketCaptureManager  @StateObject
    ├── ProfileManager        @StateObject
    └── WebhookManager        @StateObject

CLIRunner (独立，不依赖上述 Manager)
    └── 直接调用 shell 命令实现功能

AppThrottlerEntry (@main)
    ├── CLI → CLIRunner.run() → exit(0)
    └── GUI → NSApplication.run() → ContentView
```

## PF 锚点命名规范

```
appthrottler              ← 主锚点（限速规则）
appthrottler/fault        ← 子锚点（故障注入规则）
```

限速和故障注入使用不同的子锚点，互不干扰。

## dnctl 管道编号规范

- 限速管道：从 100 开始，每个应用占用 2 个管道（下载/上传）
- 编号公式：`downPipe = 100 + (PID % 900)`, `upPipe = downPipe + 1`

## 文件存储位置

```
~/Library/Application Support/AppThrottler/
    └── Profiles/           ← 保存的测试配置 JSON 文件

~/Documents/AppThrottler/
    └── Reports/            ← 导出的测试报告 HTML 文件

$TMPDIR/
    ├── appthrottler_*.pcap          ← 抓包文件
    └── appthrottler_capture.sh      ← 抓包脚本
```
