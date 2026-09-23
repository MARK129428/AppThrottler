# 开发指南

## 环境要求

- macOS 14.0+ (Sonoma)
- Xcode Command Line Tools（提供 `swiftc`）
- 可选：Xcode.app（用于调试和 Interface Builder）
- 可选：xcodegen（用于生成 `.xcodeproj`）

## 快速开始

```bash
cd ~/Desktop/AppThrottler

# 构建
./build.sh

# 运行 GUI
open build/AppThrottler.app

# 运行 CLI
./cli list
./cli apply --pid 1234 --download 1000
```

## 构建系统

### build.sh
主构建脚本，执行以下步骤：
1. 清理 `build/` 目录
2. 创建 `.app` bundle 结构
3. 生成 `Info.plist`（填充实际值，非 Xcode 变量）
4. 复制 `AppIcon.icns` 到 Resources
5. 编译所有 Swift 源文件 → `Contents/MacOS/AppThrottler`

### 添加新源文件
修改 `build.sh` 的 `SOURCES` 数组：
```bash
SOURCES=(
    ...
    "$SRC_DIR/YourNewFile.swift"   # ← 添加这行
)
```
同步修改 `Makefile`。

### Makefile
提供 `make build`、`make run`、`make clean` 三个目标。
自动检测 CPU 架构（arm64 / x86_64）。

## 开发工作流

### 1. 修改代码
```bash
# 编辑任意 .swift 文件
vim AppThrottler/YourFile.swift
```

### 2. 编译检查
```bash
./build.sh
# 确保 "Build succeeded" 且无 error
```

### 3. 测试 GUI
```bash
killall AppThrottler 2>/dev/null
open build/AppThrottler.app
```

### 4. 测试 CLI
```bash
./cli list
./cli help
```

## 调试技巧

### 查看编译错误
```bash
./build.sh 2>&1 | grep "error:"
```

### 查看运行时日志
```bash
# GUI 模式的系统日志
log show --predicate 'process == "AppThrottler"' --last 1m

# 用 Console.app 查看实时日志
open -a Console
```

### 检查 PF 规则
```bash
# 查看所有锚点
sudo pfctl -s Anchors

# 查看 appthrottler 锚点的规则
sudo pfctl -a appthrottler -s rules

# 查看 dnctl 管道
sudo dnctl pipe show
```

### 手动清理限速残留
```bash
# 清除所有 appthrottler 规则
sudo pfctl -a appthrottler -F rules
sudo pfctl -a appthrottler/fault -F rules

# 删除所有 dnctl 管道
sudo dnctl flush

# 恢复 hosts 文件（如有故障注入残留）
sudo cp /etc/hosts.appthrottler.bak /etc/hosts 2>/dev/null
sudo dscacheutil -flushcache
```

## 代码风格

- **Swift 5.9** 语法
- **2 空格缩进**
- **struct 优先**：视图用 struct，Manager 用 class
- **`@MainActor`**：所有 Manager 类标注 `@MainActor`
- **`@Published`**：UI 绑定的状态属性
- **不用注释**：除非有非直觉的约束
- **命名**：camelCase 变量/方法，PascalCase 类型

## 添加新 Tab 的完整步骤

1. 在 `ContentView.swift` 的 `RightTab` 枚举中添加 case
2. 创建 `YourNewView: View` struct
3. 在 `switch selectedTab` 中添加 case 分支
4. 如需新 Manager → 创建独立文件 + 添加 `@StateObject`
5. 在 `build.sh` 的 SOURCES 中添加新文件
6. 运行 `./build.sh` 编译

## 发布检查清单

- [ ] `./build.sh` 零 error
- [ ] GUI 正常启动，所有 Tab 可切换
- [ ] CLI `list`、`help`、`status` 正常
- [ ] 限速功能正常（需管理员权限）
- [ ] 故障注入启用/停用正常
- [ ] 抓包启停正常
- [ ] 测试报告能正常生成并打开
- [ ] 图标显示正常
