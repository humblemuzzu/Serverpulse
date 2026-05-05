# ServerPulse

macOS menu bar app that monitors your Linux server in real-time via SSH.

One glance at your menu bar shows the load average. Click for the full dashboard — CPU, memory, disk, network, Docker containers, top processes — all refreshed every 30 seconds.

**No code editing required** — configure your server from the in-app Settings window.

![ServerPulse Screenshot](https://github.com/user-attachments/assets/placeholder.png)

## Features

- **In-app Settings** — configure SSH host, IP, dashboard URL, refresh interval from the UI
- **Test Connection** — verify SSH works before saving
- **Menu bar at a glance** — pulse icon + load average, always visible
- **CPU** — load averages (1/5/15m), usage breakdown (user/sys/wait), segmented progress bar
- **Memory** — RAM used/total/free, swap, buffer cache
- **Disk** — usage with free space remaining
- **Network** — active connections, listening ports, total traffic, live bandwidth rate
- **Docker containers** — all containers with status, CPU%, memory usage
- **Top processes** — top 5 by CPU with user info
- **Color-coded bars** — cyan (healthy) → amber (warning 65%+) → red (critical 85%+)
- **Quick actions** — refresh, open SSH terminal, open dashboard, copy server IP
- **Dark HUD aesthetic** — forced dark mode, monospace fonts, terminal-inspired design
- **Searchable** — installs to ~/Applications, works with Spotlight and Raycast
- **Zero dependencies** — single Swift file, no Xcode required, compiles with `swiftc`

## Requirements

- macOS 12+ (Apple Silicon)
- SSH access to a Linux server (key-based auth)
- [Tailscale](https://tailscale.com) recommended for easy connectivity (but any SSH works)

## Install

```bash
git clone https://github.com/humblemuzzu/Serverpulse.git
cd Serverpulse
chmod +x build.sh
./build.sh
```

This builds the app and installs it to `~/Applications/ServerPulse.app` — searchable via Spotlight and Raycast.

## Setup

1. Launch ServerPulse — it appears in your menu bar as a pulse icon
2. On first launch, the **Settings window** opens automatically
3. Enter your SSH host (e.g. `root@my-server` or `root@1.2.3.4`)
4. Click **Test Connection** to verify
5. Click **Save & Connect**

That's it. ServerPulse starts monitoring immediately.

### Settings

Open anytime via the menu → **⚙ Settings** (or `⌘,`):

| Setting | Description |
|---------|-------------|
| SSH Host | Primary SSH target — Tailscale hostname or `user@ip` |
| Fallback Host | Optional backup if primary is unreachable |
| Public IP | For the "Copy Server IP" quick action |
| Dashboard URL | Opens your Coolify/Portainer/admin panel |
| Refresh Interval | How often to poll (10–300 seconds) |
| SSH Timeout | Max wait before marking failed (5–60 seconds) |

All settings are stored locally via macOS UserDefaults. Nothing leaves your machine.

### Auto-start on login

System Settings → General → Login Items → click `+` → select ServerPulse

## How it works

Every N seconds, ServerPulse runs a single SSH command that collects system metrics using standard Linux tools (`top`, `free`, `df`, `ss`, `docker stats`, `ps`). The output is parsed and displayed in a SwiftUI card embedded in a native `NSMenu`.

### Server requirements

Your server needs these standard tools (present on any modern Linux):
- `top`, `free`, `df`, `ss`, `ps`, `awk`, `nproc`
- `docker` (for container monitoring — gracefully skipped if unavailable)
- Key-based SSH auth (password auth is not supported)

### Menu bar icon

The pulse/heartbeat waveform is a template image — macOS automatically adapts it for light and dark menu bars. The number next to it is the 1-minute load average.

## Architecture

```
ServerPulse.app
├── main.swift          # Everything — single file, ~1000 lines
│   ├── AppConfig       # UserDefaults-backed settings
│   ├── Theme           # Colors, fonts, opacity levels
│   ├── Data Models     # ServerData, ContainerInfo, ProcessInfo
│   ├── SwiftUI Views   # ServerCardView, SettingsView, SegmentedBar
│   ├── ServerMonitor   # SSH execution + output parsing
│   └── AppDelegate     # Menu bar, timer, window management
├── Info.plist          # App bundle metadata (LSUIElement = menu bar only)
└── build.sh            # Build + install script
```

No Xcode project. No package manager. Just `swiftc` with `-framework Cocoa -framework SwiftUI`.

## Customization

Beyond the Settings UI, you can tweak these in code:

| What | Where |
|------|-------|
| Card width | `Config.cardWidth` (default: 340pt) |
| Bar segments | `SegmentedBar` init (default: 30) |
| Warning color threshold | `Theme.barTint()` (default: 65%) |
| Critical color threshold | `Theme.barTint()` (default: 85%) |
| Process count | `data.topProcesses.prefix(5)` |

## License

MIT
