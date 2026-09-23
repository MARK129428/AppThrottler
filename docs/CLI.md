# CLI 参考手册

## 概述

AppThrottler 提供完整的命令行接口，可用于终端交互和 AI 自动化。
二进制路径：`~/Desktop/AppThrottler/build/AppThrottler.app/Contents/MacOS/AppThrottler`
快捷脚本：`~/Desktop/AppThrottler/cli`

## 命令列表

### `list` — 列出运行中的进程

```bash
AppThrottler list
```

输出：PID 和进程名的表格。
不需要 sudo。

### `apply` — 应用网络限速

```bash
AppThrottler apply --pid <pid> [选项]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--pid` | 进程 ID（必填） | - |
| `--download` | 下载限速 (Kbps) | 0（不限） |
| `--upload` | 上传限速 (Kbps) | 0（不限） |
| `--latency` | 延迟注入 (ms) | 0 |
| `--loss` | 丢包率 (0.0-1.0) | 0 |

**需要 sudo。**

示例：
```bash
# 限速 1Mbps 下载 + 200ms 延迟
sudo AppThrottler apply --pid 1234 --download 1000 --latency 200

# 10% 丢包
sudo AppThrottler apply --pid 1234 --loss 0.1

# 仅延迟不限速
sudo AppThrottler apply --pid 1234 --latency 500
```

### `remove-all` — 清除所有限速

```bash
sudo AppThrottler remove-all
```

清除所有 dnctl 管道和 PF 锚点规则。
**需要 sudo。**

### `status` — 查看当前限速状态

```bash
AppThrottler status
```

输出当前活动的 dnctl 管道信息。
不需要 sudo。

### `capture` — 抓包

```bash
AppThrottler capture --pid <pid> [--duration <秒>]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--pid` | 进程 ID（必填） | - |
| `--duration` | 抓包时长（秒） | 10 |

**需要 sudo。**

示例：
```bash
# 抓 30 秒
sudo AppThrottler capture --pid 1234 --duration 30
```

### `help` — 显示帮助

```bash
AppThrottler help
AppThrottler --help
AppThrottler -h
```

## AI 自动化集成

### 推荐工作流

```bash
#!/bin/bash
BIN=~/Desktop/AppThrottler/build/AppThrottler.app/Contents/MacOS/AppThrottler

# 1. 找到目标应用的 PID
PID=$($BIN list | grep "Safari" | awk '{print $1}')

# 2. 应用 3G 网络条件
sudo $BIN apply --pid $PID --download 1000 --upload 384 --latency 200 --loss 0.01

# 3. 执行测试...

# 4. 抓包验证
sudo $BIN capture --pid $PID --duration 10

# 5. 清理
sudo $BIN remove-all
```

### 常见网络条件速查

| 场景 | download | upload | latency | loss |
|------|----------|--------|---------|------|
| 2G GPRS | 50 | 20 | 500 | 0.02 |
| 3G | 1000 | 384 | 200 | 0.01 |
| 4G LTE | 10000 | 5000 | 50 | 0.005 |
| 弱 WiFi | 500 | 200 | 300 | 0.10 |
| 高铁 | 2000 | 1000 | 500 | 0.20 |
| 电梯 | 100 | 50 | 1000 | 0.30 |

### 常见故障注入场景

```bash
# 模拟 DNS 超时（阻断 UDP 53）
sudo pfctl -a appthrottler/fault -f - <<< 'block drop quick proto udp from any to any port 53'

# 模拟 TCP RST（阻断并返回 RST）
sudo pfctl -a appthrottler/fault -f - <<< 'block return quick proto tcp from any to any'

# 模拟 SSL 错误（阻断 443）
sudo pfctl -a appthrottler/fault -f - <<< 'block drop quick proto tcp from any to any port 443'

# 清除故障注入
sudo pfctl -a appthrottler/fault -F rules
```

## 错误码

CLI 退出码：
- `0` — 成功
- `1` — 参数错误或无网络连接

错误输出到 stderr，正常输出到 stdout。
