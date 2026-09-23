# Changelog

All notable changes to AppThrottler will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2025-01-22

### Added
- **全面自定义主题系统** — 4 套预设主题（深蓝科技/暗紫夜空/暗绿终端/跟随系统），毛玻璃 (Glass) 效果
- **macOS 原生 UI 大重构** — NavigationSplitView 三栏布局、Swift Charts 流量图、ContentUnavailableView、原生搜索栏
- **HTTP 调试** — 请求/响应查看、请求重放、cURL 导入导出、会话保存/加载、请求 Diff 对比、13 种资源类型分类
- **故障注入** — DNS 超时/失败/劫持、TCP 连接重置、HTTPS 证书错误
- **实时流量监控** — Swift Charts 面积折线图、流量统计（总量/峰值/均值）
- **场景编排** — 网络波动/断网恢复/弱网渐变/丢包递增，按时间线自动切换
- **测试报告** — HTML 格式导出，含限速配置 + 流量统计 + 故障记录
- **测试配置管理** — 保存/加载/导入/导出 JSON 配置文件
- **iPhone 代理限速** — Mac 端 HTTP CONNECT 代理，iPhone 流量经过限速管道
- **REST API Server** — 完整 HTTP API，支持远程控制所有功能
- **CLI 模式** — 完整命令行接口，支持 AI 自动化集成
- **Webhook 通知** — 操作时自动 POST JSON 到指定 URL
- **AppleScript 桥接** — 支持外部脚本控制
- **MenuBar** — 原生菜单栏（编辑/视图）
- **版本号** — 2.0.0

### Changed
- 全面替换硬编码颜色为语义色 token（130+ 处）
- 所有视图使用 `@EnvironmentObject` 注入主题
- 使用 `NavigationSplitView` 替代 `HSplitView`
- 使用 `Picker(.segmented)` 替代自定义胶囊 Tab 栏
- 流量图从手动画矩形升级为 Swift Charts

## [1.0.0] - 2025-01-20

### Added
- 基础限速功能（下载/上传/延迟/丢包）
- 10 种网络预设（2G~5G 等）
- 进程列表显示
- 抓包功能（tcpdump）
- 操作日志
