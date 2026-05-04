import Cocoa
import SwiftUI

// ┌──────────────────────────────────────────────────────────────────┐
// │  ServerPulse — Menu bar server monitor via Tailscale SSH        │
// │  Inspired by AgentsBar's terminal HUD aesthetic                 │
// └──────────────────────────────────────────────────────────────────┘

// MARK: - Configuration
struct Config {
    // ── Edit these for your server ──────────────────────────────────
    static let sshHost         = "root@your-server"       // Tailscale hostname or user@host
    static let sshHostFallback = "root@your-server-ip"    // Fallback IP if hostname fails
    static let serverIP        = "0.0.0.0"                // Your server's public IP
    static let coolifyURL      = "http://your-server:8000" // Coolify dashboard URL (optional)
    // ────────────────────────────────────────────────────────────────
    static let refreshInterval: TimeInterval = 30
    static let sshTimeout = 12
    static let cardWidth: CGFloat = 340
}

// MARK: - Theme
struct Theme {
    static let primary    = Color.white.opacity(0.92)
    static let secondary  = Color.white.opacity(0.50)
    static let tertiary   = Color.white.opacity(0.28)
    static let border     = Color.white.opacity(0.08)
    static let track      = Color.white.opacity(0.10)

    // Accent — muted cyan for that monitoring-dashboard feel
    static let accent     = Color(red: 0.35, green: 0.82, blue: 0.92)
    static let accentDim  = Color(red: 0.35, green: 0.82, blue: 0.92).opacity(0.20)
    static let warn       = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let crit       = Color(red: 1.0, green: 0.38, blue: 0.38)

    static let headerFont = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let valueFont  = Font.system(size: 11.5, weight: .medium, design: .monospaced)
    static let labelFont  = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let smallFont  = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let tinyFont   = Font.system(size: 9, weight: .regular, design: .monospaced)

    static func barTint(for percent: Double) -> Color {
        if percent >= 85 { return crit }
        if percent >= 65 { return warn }
        return accent
    }
}

// MARK: - Data Models
struct ServerData {
    var hostname = ""; var uptimeSeconds = 0
    var load1 = 0.0; var load5 = 0.0; var load15 = 0.0; var cpuCores = 1
    var cpuUser = 0.0; var cpuSys = 0.0; var cpuIdle = 100.0; var cpuWait = 0.0
    var memTotal: Int64 = 0; var memUsed: Int64 = 0
    var memAvailable: Int64 = 0; var memBuffCache: Int64 = 0
    var swapTotal: Int64 = 0; var swapUsed: Int64 = 0
    var diskTotal: Int64 = 0; var diskUsed: Int64 = 0; var diskAvail: Int64 = 0
    var diskPercent = "0%"
    var netConnections = 0; var netListening = 0
    var netIface = "eth0"; var netRxBytes: Int64 = 0; var netTxBytes: Int64 = 0
    var containers: [ContainerInfo] = []
    var topProcesses: [ProcessInfo] = []
    var kernel = ""; var os = ""

    var cpuBusy: Double { 100.0 - cpuIdle }
    var memPercent: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) * 100 : 0 }
    var swapPercent: Double { swapTotal > 0 ? Double(swapUsed) / Double(swapTotal) * 100 : 0 }
    var diskPercentNum: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) * 100 : 0 }
    var loadRatio: Double { cpuCores > 0 ? load1 / Double(cpuCores) : 0 }
}

struct ContainerInfo {
    var name, cpuPercent, memUsage, memPercent, netIO, pids: String
    var state, status, image, ports: String

    var friendlyName: String {
        if name.count > 30 && name.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" || $0 == "_" }) {
            var img = image.split(separator: "/").last.map(String.init) ?? image
            if let c = img.firstIndex(of: ":") { img = String(img[..<c]) }
            return img.isEmpty ? String(name.prefix(18)) : img
        }
        return name
    }
    var isRunning: Bool { state.lowercased() == "running" }
    var memShort: String { memUsage.components(separatedBy: " / ").first?.trimmingCharacters(in: .whitespaces) ?? memUsage }
}

struct ProcessInfo {
    var user: String; var cpuPercent: Double; var memPercent: Double; var command: String
    var shortCommand: String {
        let base = command.split(separator: "/").last.map(String.init) ?? command
        return String(base.prefix(20))
    }
}

// MARK: - Formatting
func fmtBytes(_ b: Int64) -> String {
    if b >= 1_073_741_824 { return String(format: "%.1f GB", Double(b) / 1_073_741_824) }
    if b >= 1_048_576 { return String(format: "%.1f MB", Double(b) / 1_048_576) }
    if b >= 1024 { return String(format: "%.0f KB", Double(b) / 1024) }
    return "\(b) B"
}

func fmtRate(_ bps: Double) -> String {
    if bps >= 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
    if bps >= 1024 { return String(format: "%.1f KB/s", bps / 1024) }
    return String(format: "%.0f B/s", bps)
}

func fmtUptime(_ s: Int) -> String {
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "\(d)d \(h)h \(m)m" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

// MARK: - SwiftUI Components

struct SegmentedBar: View {
    let value: Double  // 0–100
    let segments: Int
    let tint: Color

    init(_ value: Double, segments: Int = 30, tint: Color? = nil) {
        self.value = min(max(value, 0), 100)
        self.segments = segments
        self.tint = tint ?? Theme.barTint(for: value)
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(i) / Double(segments) * 100 < value ? tint : Theme.track)
                    .frame(height: 6)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.headerFont)
            .foregroundColor(Theme.secondary)
            .kerning(1.8)
    }
}

struct HairlineDivider: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 0.5)
    }
}

struct MetricLine: View {
    let label: String
    let value: String
    let detail: String?

    init(_ label: String, _ value: String, _ detail: String? = nil) {
        self.label = label; self.value = value; self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(Theme.labelFont)
                .foregroundColor(Theme.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(Theme.valueFont)
                .foregroundColor(Theme.primary)
            if let d = detail {
                Spacer()
                Text(d)
                    .font(Theme.smallFont)
                    .foregroundColor(Theme.tertiary)
            }
        }
    }
}

// MARK: - Server Card View
struct ServerCardView: View {
    let data: ServerData
    let rxRate: Double
    let txRate: Double
    let lastUpdate: Date?
    let healthEmoji: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            sectionDivider
            cpuSection
            sectionDivider
            memorySection
            sectionDivider
            diskSection
            sectionDivider
            networkSection
            sectionDivider
            containersSection
            if !data.topProcesses.isEmpty {
                sectionDivider
                processesSection
            }
            footerSection
        }
        .frame(width: Config.cardWidth)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Pulse dot — animated-feeling
                Circle()
                    .fill(data.loadRatio >= 0.9 ? Theme.crit :
                          data.loadRatio >= 0.7 ? Theme.warn : Theme.accent)
                    .frame(width: 7, height: 7)
                Text(data.hostname)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.primary)
                Text("·")
                    .foregroundColor(Theme.tertiary)
                Text("Up \(fmtUptime(data.uptimeSeconds))")
                    .font(Theme.labelFont)
                    .foregroundColor(Theme.secondary)
            }
            Text("\(data.os) · \(data.kernel) · \(data.cpuCores) cores")
                .font(Theme.tinyFont)
                .foregroundColor(Theme.tertiary)
                .padding(.leading, 15)
        }
        .padding(.bottom, 6)
    }

    // MARK: CPU
    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "cpu")
            MetricLine("Load", "\(f2(data.load1))  \(f2(data.load5))  \(f2(data.load15))", "1 / 5 / 15m")
            MetricLine("Usage", "\(f1(data.cpuBusy))% busy",
                       "\(f1(data.cpuUser)) usr · \(f1(data.cpuSys)) sys · \(f1(data.cpuWait)) wa")
            HStack(spacing: 8) {
                SegmentedBar(data.cpuBusy)
                Text("\(f1(data.cpuBusy))%")
                    .font(Theme.smallFont)
                    .foregroundColor(Theme.barTint(for: data.cpuBusy))
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Memory
    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "memory")
            MetricLine("RAM", "\(fmtBytes(data.memUsed)) / \(fmtBytes(data.memTotal))",
                       "\(fmtBytes(data.memAvailable)) free")
            HStack(spacing: 8) {
                SegmentedBar(data.memPercent)
                Text("\(f1(data.memPercent))%")
                    .font(Theme.smallFont)
                    .foregroundColor(Theme.barTint(for: data.memPercent))
                    .frame(width: 42, alignment: .trailing)
            }
            if data.swapTotal > 0 {
                MetricLine("Swap", "\(fmtBytes(data.swapUsed)) / \(fmtBytes(data.swapTotal))")
                HStack(spacing: 8) {
                    SegmentedBar(data.swapPercent)
                    Text("\(f1(data.swapPercent))%")
                        .font(Theme.smallFont)
                        .foregroundColor(Theme.barTint(for: data.swapPercent))
                        .frame(width: 42, alignment: .trailing)
                }
            }
            MetricLine("Buffers", fmtBytes(data.memBuffCache))
        }
        .padding(.vertical, 8)
    }

    // MARK: Disk
    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "disk")
            MetricLine("Root", "\(fmtBytes(data.diskUsed)) / \(fmtBytes(data.diskTotal))",
                       "\(fmtBytes(data.diskAvail)) free")
            HStack(spacing: 8) {
                SegmentedBar(data.diskPercentNum)
                Text(data.diskPercent)
                    .font(Theme.smallFont)
                    .foregroundColor(Theme.barTint(for: data.diskPercentNum))
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Network
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel(text: "network")
                Text(data.netIface)
                    .font(Theme.tinyFont)
                    .foregroundColor(Theme.tertiary)
            }
            MetricLine("Conns", "\(data.netConnections) established", "\(data.netListening) listening")
            MetricLine("Total", "↓ \(fmtBytes(data.netRxBytes))  ↑ \(fmtBytes(data.netTxBytes))")
            if rxRate > 0 || txRate > 0 {
                MetricLine("Rate", "↓ \(fmtRate(rxRate))  ↑ \(fmtRate(txRate))")
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Containers
    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let running = data.containers.filter(\.isRunning).count
            HStack(spacing: 6) {
                SectionLabel(text: "containers")
                Text("\(running)/\(data.containers.count)")
                    .font(Theme.tinyFont)
                    .foregroundColor(running == data.containers.count ? Theme.accent : Theme.warn)
            }

            // Column header
            HStack(spacing: 0) {
                Text("    Name")
                    .frame(width: 160, alignment: .leading)
                Text("CPU")
                    .frame(width: 60, alignment: .trailing)
                Text("MEM")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(Theme.tinyFont)
            .foregroundColor(Theme.tertiary)

            ForEach(Array(data.containers.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(c.isRunning ? Theme.accent.opacity(0.8) : Theme.crit.opacity(0.5))
                            .frame(width: 5, height: 5)
                        Text(c.friendlyName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(width: 160, alignment: .leading)

                    Text(c.cpuPercent)
                        .frame(width: 60, alignment: .trailing)
                    Text(c.memShort)
                        .frame(width: 80, alignment: .trailing)
                }
                .font(Theme.smallFont)
                .foregroundColor(c.isRunning ? Theme.primary.opacity(0.85) : Theme.tertiary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Processes
    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "top processes")

            HStack(spacing: 0) {
                Text("Command")
                    .frame(width: 150, alignment: .leading)
                Text("CPU")
                    .frame(width: 55, alignment: .trailing)
                Text("MEM")
                    .frame(width: 55, alignment: .trailing)
                Text("User")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(Theme.tinyFont)
            .foregroundColor(Theme.tertiary)

            ForEach(Array(data.topProcesses.prefix(5).enumerated()), id: \.offset) { _, p in
                HStack(spacing: 0) {
                    Text(p.shortCommand)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 150, alignment: .leading)
                    Text("\(f1(p.cpuPercent))%")
                        .frame(width: 55, alignment: .trailing)
                    Text("\(f1(p.memPercent))%")
                        .frame(width: 55, alignment: .trailing)
                    Text(p.user)
                        .lineLimit(1)
                        .frame(width: 60, alignment: .trailing)
                }
                .font(Theme.smallFont)
                .foregroundColor(Theme.primary.opacity(0.75))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Footer
    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineDivider()
            if let t = lastUpdate {
                let fmt = { () -> String in
                    let f = DateFormatter(); f.dateFormat = "h:mm:ss a"; return f.string(from: t)
                }()
                HStack {
                    Spacer()
                    Text("Updated \(fmt) · every \(Int(Config.refreshInterval))s")
                        .font(Theme.tinyFont)
                        .foregroundColor(Theme.tertiary)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }

    private var sectionDivider: some View { HairlineDivider() }

    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
}

// MARK: - Loading / Error Views
struct LoadingCardView: View {
    var body: some View {
        VStack(spacing: 10) {
            SectionLabel(text: "connecting")
            Text("Waiting for server…")
                .font(Theme.labelFont)
                .foregroundColor(Theme.tertiary)
        }
        .frame(width: Config.cardWidth)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }
}

struct ErrorCardView: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECTION FAILED")
                .font(Theme.headerFont)
                .foregroundColor(Theme.crit)
                .kerning(1.8)
            Text(message)
                .font(Theme.labelFont)
                .foregroundColor(Theme.secondary)
            Text("Host: \(Config.sshHost)")
                .font(Theme.tinyFont)
                .foregroundColor(Theme.tertiary)
            Text("Check Tailscale is connected")
                .font(Theme.tinyFont)
                .foregroundColor(Theme.tertiary)
        }
        .frame(width: Config.cardWidth, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - Hosting View (kills vibrancy for crisp text)
class CardHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}

// MARK: - Pulse Icon
func makePulseIcon() -> NSImage {
    let w: CGFloat = 18, h: CGFloat = 18
    let image = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
        let path = NSBezierPath()
        // EKG / heartbeat waveform
        path.move(to: NSPoint(x: 1, y: 9))
        path.line(to: NSPoint(x: 4.5, y: 9))
        path.line(to: NSPoint(x: 6.5, y: 14))
        path.line(to: NSPoint(x: 9, y: 3))
        path.line(to: NSPoint(x: 11, y: 12))
        path.line(to: NSPoint(x: 13, y: 9))
        path.line(to: NSPoint(x: 17, y: 9))
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.stroke()
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - Server Monitor
class ServerMonitor {
    private(set) var data: ServerData?
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
    private(set) var isLoading = false
    private var prevRx: Int64 = 0, prevTx: Int64 = 0, prevTime: Date?
    private(set) var rxRate = 0.0, txRate = 0.0

    private let script = """
    echo "HOSTNAME=$(hostname)" && \\
    echo "UPTIME_S=$(awk '{print int($1)}' /proc/uptime)" && \\
    echo "LOAD_1=$(awk '{print $1}' /proc/loadavg)" && \\
    echo "LOAD_5=$(awk '{print $2}' /proc/loadavg)" && \\
    echo "LOAD_15=$(awk '{print $3}' /proc/loadavg)" && \\
    echo "CPU_CORES=$(nproc)" && \\
    top -bn1 | awk '/^%?Cpu/{for(i=1;i<=NF;i++){if($i~"us")printf "CPU_USER=%s\\n",$(i-1);if($i~"sy")printf "CPU_SYS=%s\\n",$(i-1);if($i~"id")printf "CPU_IDLE=%s\\n",$(i-1);if($i~"wa")printf "CPU_WAIT=%s\\n",$(i-1)}}' && \\
    free -b | awk '/Mem:/{printf "MEM_TOTAL=%s\\nMEM_USED=%s\\nMEM_AVAILABLE=%s\\nMEM_BUFF_CACHE=%s\\n",$2,$3,$7,$6}/Swap:/{printf "SWAP_TOTAL=%s\\nSWAP_USED=%s\\n",$2,$3}' && \\
    df -B1 / | awk 'NR==2{printf "DISK_TOTAL=%s\\nDISK_USED=%s\\nDISK_AVAIL=%s\\nDISK_PERCENT=%s\\n",$2,$3,$4,$5}' && \\
    echo "NET_CONN=$(ss -tun state established 2>/dev/null | tail -n +2 | wc -l)" && \\
    echo "NET_LISTEN=$(ss -tln 2>/dev/null | tail -n +2 | wc -l)" && \\
    awk '/eth0:|ens/{gsub(/:/,"",$1);printf "NET_IFACE=%s\\nNET_RX=%s\\nNET_TX=%s\\n",$1,$2,$10}' /proc/net/dev && \\
    echo "KERNEL=$(uname -r)" && \\
    echo "OS=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d\\\" -f2)" && \\
    echo "===DOCKER_STATS===" && \\
    docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.PIDs}}" 2>/dev/null && \\
    echo "===END_DOCKER_STATS===" && \\
    echo "===DOCKER_INFO===" && \\
    docker ps -a --format "{{.Names}}|{{.State}}|{{.Status}}|{{.Image}}|{{.Ports}}" 2>/dev/null && \\
    echo "===END_DOCKER_INFO===" && \\
    echo "===TOP_PROCS===" && \\
    ps aux --sort=-%cpu | awk 'NR>1&&NR<=8{cmd="";for(i=11;i<=NF;i++)cmd=cmd" "$i;printf "%s|%s|%s|%s\\n",$1,$3,$4,cmd}' && \\
    echo "===END_TOP_PROCS==="
    """

    enum Health { case green, yellow, red }

    var health: Health {
        guard let d = data else { return lastError != nil ? .red : .green }
        if d.loadRatio >= 0.90 || d.memPercent >= 90 || d.diskPercentNum >= 90 { return .red }
        if d.loadRatio >= 0.70 || d.memPercent >= 80 || d.diskPercentNum >= 80 { return .yellow }
        return .green
    }

    func refresh(completion: @escaping (Bool) -> Void) {
        guard !isLoading else { completion(false); return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let out = self.ssh(Config.sshHost) ?? self.ssh(Config.sshHostFallback)
            DispatchQueue.main.async {
                self.isLoading = false
                if let out = out {
                    self.parse(out)
                    self.lastUpdate = Date()
                    self.lastError = nil
                    completion(true)
                } else {
                    self.lastError = "SSH connection timed out"
                    completion(false)
                }
            }
        }
    }

    private func ssh(_ host: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-o", "ConnectTimeout=\(Config.sshTimeout)",
                       "-o", "StrictHostKeyChecking=accept-new",
                       "-o", "BatchMode=yes", host, script]
        let pipe = Pipe(); let err = Pipe()
        p.standardOutput = pipe; p.standardError = err
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        guard p.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private func parse(_ output: String) {
        var d = ServerData()
        var dStats: [String] = [], dInfo: [String] = [], procs: [String] = []
        var section = ""

        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            switch t {
            case "===DOCKER_STATS===":     section = "ds"; continue
            case "===END_DOCKER_STATS===": section = ""; continue
            case "===DOCKER_INFO===":      section = "di"; continue
            case "===END_DOCKER_INFO===":  section = ""; continue
            case "===TOP_PROCS===":        section = "tp"; continue
            case "===END_TOP_PROCS===":    section = ""; continue
            default: break
            }
            switch section {
            case "ds": dStats.append(t)
            case "di": dInfo.append(t)
            case "tp": procs.append(t)
            default:
                if let eq = t.firstIndex(of: "=") {
                    let k = String(t[..<eq]), v = String(t[t.index(after: eq)...])
                    set(key: k, val: v, d: &d)
                }
            }
        }

        // Docker stats map
        var sm: [String: (String,String,String,String,String)] = [:]
        for l in dStats {
            let p = l.components(separatedBy: "|")
            guard p.count >= 6 else { continue }
            sm[p[0]] = (p[1],p[2],p[3],p[4],p[5])
        }
        for l in dInfo {
            let p = l.components(separatedBy: "|")
            guard p.count >= 4 else { continue }
            let s = sm[p[0]]
            d.containers.append(ContainerInfo(
                name: p[0], cpuPercent: s?.0 ?? "--", memUsage: s?.1 ?? "--",
                memPercent: s?.2 ?? "--", netIO: s?.3 ?? "--", pids: s?.4 ?? "--",
                state: p[1], status: p[2], image: p[3], ports: p.count >= 5 ? p[4] : ""))
        }
        d.containers.sort { a, b in
            if a.isRunning != b.isRunning { return a.isRunning }
            return a.friendlyName.lowercased() < b.friendlyName.lowercased()
        }

        for l in procs {
            let p = l.components(separatedBy: "|")
            guard p.count >= 4 else { continue }
            let pi = ProcessInfo(user: p[0], cpuPercent: Double(p[1]) ?? 0,
                                 memPercent: Double(p[2]) ?? 0,
                                 command: p[3].trimmingCharacters(in: .whitespaces))
            if pi.cpuPercent > 0 || pi.memPercent > 0.5 { d.topProcesses.append(pi) }
        }

        // Bandwidth rate
        if d.netRxBytes > 0, let pt = prevTime {
            let elapsed = Date().timeIntervalSince(pt)
            if elapsed > 1 {
                rxRate = max(0, Double(d.netRxBytes - prevRx) / elapsed)
                txRate = max(0, Double(d.netTxBytes - prevTx) / elapsed)
            }
        }
        prevRx = d.netRxBytes; prevTx = d.netTxBytes; prevTime = Date()
        data = d
    }

    private func set(key k: String, val v: String, d: inout ServerData) {
        switch k {
        case "HOSTNAME":       d.hostname = v
        case "UPTIME_S":       d.uptimeSeconds = Int(v) ?? 0
        case "LOAD_1":         d.load1 = Double(v) ?? 0
        case "LOAD_5":         d.load5 = Double(v) ?? 0
        case "LOAD_15":        d.load15 = Double(v) ?? 0
        case "CPU_CORES":      d.cpuCores = Int(v) ?? 1
        case "CPU_USER":       d.cpuUser = Double(v) ?? 0
        case "CPU_SYS":        d.cpuSys = Double(v) ?? 0
        case "CPU_IDLE":       d.cpuIdle = Double(v) ?? 100
        case "CPU_WAIT":       d.cpuWait = Double(v) ?? 0
        case "MEM_TOTAL":      d.memTotal = Int64(v) ?? 0
        case "MEM_USED":       d.memUsed = Int64(v) ?? 0
        case "MEM_AVAILABLE":  d.memAvailable = Int64(v) ?? 0
        case "MEM_BUFF_CACHE": d.memBuffCache = Int64(v) ?? 0
        case "SWAP_TOTAL":     d.swapTotal = Int64(v) ?? 0
        case "SWAP_USED":      d.swapUsed = Int64(v) ?? 0
        case "DISK_TOTAL":     d.diskTotal = Int64(v) ?? 0
        case "DISK_USED":      d.diskUsed = Int64(v) ?? 0
        case "DISK_AVAIL":     d.diskAvail = Int64(v) ?? 0
        case "DISK_PERCENT":   d.diskPercent = v
        case "NET_CONN":       d.netConnections = Int(v) ?? 0
        case "NET_LISTEN":     d.netListening = Int(v) ?? 0
        case "NET_IFACE":      d.netIface = v
        case "NET_RX":         d.netRxBytes = Int64(v) ?? 0
        case "NET_TX":         d.netTxBytes = Int64(v) ?? 0
        case "KERNEL":         d.kernel = v
        case "OS":             d.os = v
        default: break
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let monitor = ServerMonitor()
    var timer: Timer?
    let pulseIcon = makePulseIcon()

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = pulseIcon
            btn.imagePosition = .imageLeft
            btn.title = " …"
            btn.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        }
        rebuildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: Config.refreshInterval, repeats: true) { [weak self] _ in
            self?.doRefresh()
        }
        doRefresh()
    }

    func applicationWillTerminate(_ n: Notification) { timer?.invalidate() }

    private func doRefresh() {
        if let btn = statusItem.button { btn.title = " …" }
        monitor.refresh { [weak self] _ in self?.updateUI() }
    }

    private func updateUI() {
        rebuildMenu()
        guard let btn = statusItem.button else { return }
        if let d = monitor.data {
            let load = String(format: " %.2f", d.load1)
            btn.title = load
        } else {
            btn.title = " ✕"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        menu.autoenablesItems = false

        // Stats card
        let cardItem = NSMenuItem()
        if let d = monitor.data {
            let view = ServerCardView(data: d, rxRate: monitor.rxRate, txRate: monitor.txRate,
                                      lastUpdate: monitor.lastUpdate, healthEmoji: "")
            let hosting = CardHostingView(rootView: view)
            hosting.frame.size = hosting.fittingSize
            cardItem.view = hosting
        } else if monitor.lastError != nil {
            let hosting = CardHostingView(rootView: ErrorCardView(message: monitor.lastError!))
            hosting.frame.size = hosting.fittingSize
            cardItem.view = hosting
        } else {
            let hosting = CardHostingView(rootView: LoadingCardView())
            hosting.frame.size = hosting.fittingSize
            cardItem.view = hosting
        }
        menu.addItem(cardItem)

        menu.addItem(.separator())

        // Action items — clean, standard menu items
        let refresh = NSMenuItem(title: "  ↻  Refresh Now", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let terminal = NSMenuItem(title: "  ⌨  Open Terminal", action: #selector(terminalAction), keyEquivalent: "t")
        terminal.target = self
        menu.addItem(terminal)

        let coolify = NSMenuItem(title: "  ◉  Coolify Dashboard", action: #selector(coolifyAction), keyEquivalent: "d")
        coolify.target = self
        menu.addItem(coolify)

        let ip = NSMenuItem(title: "  ⧉  Copy Server IP", action: #selector(copyIPAction), keyEquivalent: "")
        ip.target = self
        menu.addItem(ip)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "  Quit ServerPulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc func refreshAction() { doRefresh() }

    @objc func terminalAction() {
        let src = "tell application \"Terminal\"\nactivate\ndo script \"ssh \(Config.sshHost)\"\nend tell"
        if let s = NSAppleScript(source: src) { var e: NSDictionary?; s.executeAndReturnError(&e) }
    }

    @objc func coolifyAction() {
        if let u = URL(string: Config.coolifyURL) { NSWorkspace.shared.open(u) }
    }

    @objc func copyIPAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Config.serverIP, forType: .string)
    }
}

// MARK: - Entry
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
