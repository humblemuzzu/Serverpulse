# ServerPulse

macOS menu bar app that monitors your Linux server in real-time via SSH.

One glance at your menu bar shows the load average. Click for the full dashboard — CPU, memory, disk, network, Docker containers, top processes — all refreshed every 30 seconds.

![ServerPulse Screenshot](https://github.com/user-attachments/assets/placeholder.png)

## Features

- **Menu bar at a glance** — pulse icon + load average, always visible
- **CPU** — load averages (1/5/15m), usage breakdown (user/sys/wait), segmented progress bar
- **Memory** — RAM used/total/free, swap, buffer cache
- **Disk** — usage with free space remaining
- **Network** — active connections, listening ports, total traffic, live bandwidth rate
- **Docker containers** — all containers with status, CPU%, memory usage
- **Top processes** — top 5 by CPU with user info
- **Color-coded bars** — cyan (healthy) → amber (warning 65%+) → red (critical 85%+)
- **Quick actions** — refresh, open SSH terminal, open Coolify dashboard, copy server IP
- **Dark HUD aesthetic** — forced dark mode, monospace fonts, terminal-inspired design
- **Zero dependencies** — single Swift file, no Xcode required, compiles with `swiftc`

## Requirements

- macOS 12+ (Apple Silicon)
- SSH access to a Linux server
- [Tailscale](https://tailscale.com) recommended (but any SSH works)

## Setup

### 1. Configure your server

Edit `ServerPulse/main.swift` and update the `Config` struct at the top:

```swift
struct Config {
    static let sshHost         = "root@your-server"       // SSH host (Tailscale name or IP)
    static let sshHostFallback = "root@1.2.3.4"           // Fallback IP
    static let serverIP        = "1.2.3.4"                // For "Copy IP" action
    static let coolifyURL      = "http://1.2.3.4:8000"    // Coolify dashboard (optional)
    // ...
}
```

### 2. Build

```bash
chmod +x build.sh
./build.sh
```

### 3. Run

```bash
open build/ServerPulse.app
```

### 4. Auto-start on login (optional)

System Settings → General → Login Items → click `+` → select `build/ServerPulse.app`

## How it works

Every 30 seconds, ServerPulse runs a single SSH command that collects system metrics from your server using standard Linux tools (`top`, `free`, `df`, `ss`, `docker stats`, `ps`). The output is parsed and displayed in a SwiftUI card embedded in a native `NSMenu`.

The first SSH connection may require Tailscale authentication (opens browser). After that, it's cached.

### SSH requirements

Your server needs these standard tools (present on any modern Linux):
- `top`, `free`, `df`, `ss`, `ps`, `awk`, `nproc`
- `docker` (for container monitoring — gracefully skipped if unavailable)

### Menu bar icon

The pulse/heartbeat waveform is a template image — macOS automatically adapts it to light and dark menu bars. The number next to it is the 1-minute load average.

## Architecture

```
ServerPulse.app
├── main.swift          # Everything — single file, ~800 lines
│   ├── Config          # SSH host, refresh interval
│   ├── Theme           # Colors, fonts, opacity levels
│   ├── Data Models     # ServerData, ContainerInfo, ProcessInfo
│   ├── SwiftUI Views   # ServerCardView, SegmentedBar, MetricLine
│   ├── ServerMonitor   # SSH execution + output parsing
│   └── AppDelegate     # Menu bar setup, timer, actions
├── Info.plist          # App bundle metadata (LSUIElement = menu bar only)
└── build.sh            # Compile script
```

No Xcode project. No package manager. Just `swiftc` with `-framework Cocoa -framework SwiftUI`.

## Customization

| What | Where |
|------|-------|
| Refresh interval | `Config.refreshInterval` (default: 30s) |
| SSH timeout | `Config.sshTimeout` (default: 12s) |
| Card width | `Config.cardWidth` (default: 340pt) |
| Progress bar segments | `SegmentedBar` init (default: 30) |
| Warning threshold | `Theme.barTint()` (default: 65%) |
| Critical threshold | `Theme.barTint()` (default: 85%) |
| Number of processes | `data.topProcesses.prefix(5)` in `processesSection` |

## License

MIT
