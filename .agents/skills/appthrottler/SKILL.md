# AppThrottler — macOS Network Throttling & Packet Capture

Control network throttling and packet capture for any running macOS application via CLI. Useful for QA testing, network condition simulation, and debugging.

## Binary Location

```
~/Desktop/AppThrottler/build/AppThrottler.app/Contents/MacOS/AppThrottler
```

## CLI Usage

### List Running Applications

```bash
AppThrottler list
```

Output shows PID, name, and throttle status for each GUI app.

### Apply Throttle

```bash
# Throttle download to 1 Mbps with 200ms latency
AppThrottler apply --pid 1234 --download 1000 --latency 200

# Throttle both directions with packet loss
AppThrottler apply --pid 1234 --download 500 --upload 200 --latency 300 --loss 0.1

# Latency only (no speed limit)
AppThrottler apply --pid 1234 --latency 1000

# Packet loss only
AppThrottler apply --pid 1234 --loss 0.2
```

Parameters:
- `--pid <pid>` — Process ID (**required**)
- `--download <kbps>` — Download speed limit in Kbps (0 = unlimited)
- `--upload <kbps>` — Upload speed limit in Kbps (0 = unlimited)
- `--latency <ms>` — Latency in milliseconds (0 = none)
- `--loss <0.0-1.0>` — Packet loss rate, e.g. 0.1 = 10%

### Apply Network Preset

```bash
AppThrottler apply-preset --pid 1234 --preset 3g
AppThrottler apply-preset --pid 1234 --preset weak-wifi
```

Available presets:
| ID | Description |
|---|---|
| `2g` | 50/20 Kbps, 500ms delay, 2% loss |
| `3g` | 1/0.384 Mbps, 200ms delay, 1% loss |
| `4g` | 10/5 Mbps, 50ms delay, 0.5% loss |
| `5g` | 100/50 Mbps, 10ms delay |
| `weak-wifi` | 500/200 Kbps, 300ms delay, 10% loss |
| `coffee-wifi` | 5/2 Mbps, 80ms delay, 3% loss |
| `high-speed-rail` | 2/1 Mbps, 500ms delay, 20% loss |
| `elevator` | 100/50 Kbps, 1000ms delay, 30% loss |
| `packet-loss-heavy` | No speed limit, 40% loss |
| `high-latency` | No speed limit, 2000ms delay |

### Remove Throttle

```bash
# Remove from specific app
AppThrottler remove --pid 1234

# Remove all throttles
AppThrottler remove-all
```

### Check Status

```bash
AppThrottler status
```

### Packet Capture

```bash
# Capture packets for 10 seconds (default)
AppThrottler capture --pid 1234

# Capture for 30 seconds
AppThrottler capture --pid 1234 --duration 30
```

Output shows real-time packets with source/destination IP:port, protocol, length, and TCP flags.

### JSON Mode (for programmatic use)

```bash
# Pipe JSON commands via stdin
echo '{"action":"list"}' | AppThrottler --json
echo '{"action":"apply","pid":1234,"downloadKbps":1000,"latencyMs":200}' | AppThrottler --json
echo '{"action":"apply-preset","pid":1234,"presetId":"3g"}' | AppThrottler --json
echo '{"action":"remove","pid":1234}' | AppThrottler --json
echo '{"action":"status"}' | AppThrottler --json
echo '{"action":"capture","pid":1234}' | AppThrottler --json
```

JSON output format:
```json
{
  "success": true,
  "message": "...",
  "data": { ... }
}
```

## GUI Mode

Launch without arguments to open the graphical interface:

```bash
open ~/Desktop/AppThrottler/build/AppThrottler.app
```

GUI features:
- **手动设置** — Manual speed/latency/packet-loss controls with sliders
- **网络预设** — One-click network condition presets (2G through 5G, etc.)
- **场景编排** — Automated test scenarios that change conditions over time
- **测试配置** — Save/load/export test configurations as JSON files
- **抓包** — Real-time packet capture with protocol stats and pcap export
- **操作日志** — Activity log of all throttle operations

## Permissions

Throttle and capture features require administrator privileges. The CLI commands that modify network state will trigger a macOS password dialog (GUI mode) or must be run with `sudo` (CLI mode).

## Typical QA Workflow

```bash
# 1. Find the app's PID
AppThrottler list | grep Safari

# 2. Simulate 3G network
AppThrottler apply-preset --pid 456 --preset 3g

# 3. Run your tests...

# 4. Check what's throttled
AppThrottler status

# 5. Remove throttle
AppThrottler remove --pid 456
```

## Tips for AI Agents

- Always call `list` first to get the PID of the target application.
- Use `apply-preset` for common network conditions — it's simpler than specifying individual parameters.
- Use `capture` to observe what network traffic an app is generating before/after throttling.
- Combine throttle + capture for full network debugging: throttle to simulate conditions, capture to verify behavior.
- Use `remove-all` as cleanup after test sessions.
