import Darwin
import Foundation
import IOKit.ps
import SwiftUI

/// CPU, RAM, disco, bateria e rede, amostrados a cada 2 segundos.
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu: Double = 0            // 0...1
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0
    @Published private(set) var battery: Int?              // nil em Macs sem bateria
    @Published private(set) var charging = false
    @Published private(set) var downSpeed: Double = 0      // bytes/s
    @Published private(set) var upSpeed: Double = 0

    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    private var interval: TimeInterval = 2
    private var lastSample = Date.distantPast
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNet: (rx: UInt64, tx: UInt64)?
    private var timer: Timer?

    init() {
        tick()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let prefs = Prefs.shared
        guard prefs.bool(.modSystem) else { return }
        let now = Date()
        let wanted = max(prefs.double(.sysInterval), 1)
        guard now.timeIntervalSince(lastSample) >= wanted - 0.05 else { return }
        // A velocidade de rede usa o tempo real entre as duas amostras.
        interval = lastSample == .distantPast ? wanted : now.timeIntervalSince(lastSample)
        lastSample = now
        sample()
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastTicks = ticks
        }
        memoryUsed = Self.usedMemory() ?? memoryUsed

        let net = Self.networkBytes()
        if let last = lastNet {
            // Contadores de 32 bits podem dar a volta; nesse caso ignora a amostra.
            downSpeed = net.rx >= last.rx ? Double(net.rx - last.rx) / interval : 0
            upSpeed = net.tx >= last.tx ? Double(net.tx - last.tx) / interval : 0
        }
        lastNet = net

        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                      .volumeTotalCapacityKey]) {
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        }
        readBattery()
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    private static func usedMemory() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(sysconf(_SC_PAGESIZE))
    }

    private static func networkBytes() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (0, 0) }
        defer { freeifaddrs(addrs) }
        var cursor = addrs
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: ifa.pointee.ifa_name).hasPrefix("en"),
                  let data = ifa.pointee.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(stats.ifi_ibytes)
            tx += UInt64(stats.ifi_obytes)
        }
        return (rx, tx)
    }

    private func readBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            battery = current * 100 / max
            charging = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return
        }
    }
}

struct SystemView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        HStack(spacing: 14) {
            if prefs.bool(.sysCPU) {
                gauge("CPU", value: system.cpu, text: "\(Int((system.cpu * 100).rounded()))%", color: .blue)
            }
            if prefs.bool(.sysRAM) {
                gauge("RAM", value: Double(system.memoryUsed) / Double(system.memoryTotal),
                      text: bytes(Int64(system.memoryUsed)), color: .purple)
            }
            if prefs.bool(.sysDisk) {
                gauge("Disco", value: system.diskTotal > 0
                        ? 1 - Double(system.diskFree) / Double(system.diskTotal) : 0,
                      text: L("%@ livres", bytes(system.diskFree)), color: .orange)
            }
            if prefs.bool(.sysBattery), let battery = system.battery {
                gauge(system.charging ? "Carregando" : "Bateria", value: Double(battery) / 100,
                      text: "\(battery)%", color: battery <= 20 && !system.charging ? .red : .green)
            }
            if prefs.bool(.sysNetwork) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rede").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Label(speed(system.downSpeed), systemImage: "arrow.down")
                    Label(speed(system.upSpeed), systemImage: "arrow.up")
                }
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 110, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gauge(_ title: LocalizedStringKey, value: Double, text: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
                Circle().trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: value)
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .frame(width: 62, height: 62)
            Text(title).font(.system(size: 11, weight: .medium))
            Text(text).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    private func speed(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
    }
}
