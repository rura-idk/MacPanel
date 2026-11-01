import Foundation
import AppKit
import Darwin
import Combine

struct FanReading: Identifiable {
    let index: Int
    let rpm: Double
    let target: Double?
    let minimum: Double?
    let maximum: Double?
    var id: Int { index }
}

final class SystemMonitor: ObservableObject {
    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var logicalCores: Int = ProcessInfo.processInfo.activeProcessorCount
    @Published private(set) var loadAverage: Double = 0
    @Published private(set) var gpuPercent: Double? = nil
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var swapUsed: UInt64? = nil
    @Published private(set) var networkDown: UInt64 = 0
    @Published private(set) var networkUp: UInt64 = 0
    @Published private(set) var diskUsed: UInt64 = 0
    @Published private(set) var diskTotal: UInt64 = 0
    @Published private(set) var diskRead: UInt64? = nil
    @Published private(set) var diskWrite: UInt64? = nil
    @Published private(set) var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    // This is a chosen PMU/SoC sensor, not necessarily the hottest CPU core.
    @Published private(set) var temperatureCelsius: Double? = nil
    @Published private(set) var fans: [FanReading] = []

    private var temperatureReadingInProgress = false
    private var hardwareReadingInProgress = false
    private var previousTicks: [UInt64]?
    private var previousNetwork: (rx: UInt64, tx: UInt64)?
    private var previousNetworkTime: TimeInterval?
    private var previousDisk: (read: UInt64, write: UInt64, time: TimeInterval)?
    private var counter = 0

    func update() {
        updateCPU()
        updateMemory()
        updateNetwork()
        uptime = ProcessInfo.processInfo.systemUptime
        thermalState = ProcessInfo.processInfo.thermalState
        if counter % 2 == 0 { updateHardware() }
        if counter % 6 == 0 {
            updateDisk()
            updateTemperature()
        }
        counter += 1
    }

    private func sensorURL(_ name: String) -> URL? {
        guard let base = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let url = base.appendingPathComponent(name)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func readSensor(_ url: URL) -> Data? {
        let process = Process()
        process.executableURL = url
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Helpers produce small bounded output and do not require sudo.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 && data.count < 65_536 ? data : nil
        } catch { return nil }
    }

    private func updateTemperature() {
        guard !temperatureReadingInProgress, let url = sensorURL("MacPanelSensor") else { return }
        temperatureReadingInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let reading: Double? = self?.readSensor(url).flatMap { data in
                guard let text = String(data: data, encoding: .utf8),
                      let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                      number > 0 && number < 150 else { return nil }
                return number
            }
            DispatchQueue.main.async { [weak self] in
                self?.temperatureCelsius = reading
                self?.temperatureReadingInProgress = false
            }
        }
    }

    private func updateHardware() {
        guard !hardwareReadingInProgress, let url = sensorURL("MacPanelHardware") else { return }
        hardwareReadingInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result: [String: Any]? = self?.readSensor(url).flatMap { data in
                (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hardwareReadingInProgress = false
                guard let result else {
                    self.fans = []
                    self.gpuPercent = nil
                    self.diskRead = nil
                    self.diskWrite = nil
                    self.previousDisk = nil
                    return
                }
                let rawFans = result["fans"] as? [[String: Any]] ?? []
                self.fans = rawFans.compactMap { item in
                    guard let index = (item["index"] as? NSNumber)?.intValue,
                          let rpm = (item["rpm"] as? NSNumber)?.doubleValue else { return nil }
                    return FanReading(index: index, rpm: rpm,
                                      target: (item["target"] as? NSNumber)?.doubleValue,
                                      minimum: (item["minimum"] as? NSNumber)?.doubleValue,
                                      maximum: (item["maximum"] as? NSNumber)?.doubleValue)
                }
                self.gpuPercent = (result["gpuPercent"] as? NSNumber)?.doubleValue
                if let read = (result["diskRead"] as? NSNumber)?.uint64Value,
                   let write = (result["diskWrite"] as? NSNumber)?.uint64Value {
                    let now = ProcessInfo.processInfo.systemUptime
                    if let old = self.previousDisk, now > old.time {
                        let dt = now - old.time
                        self.diskRead = UInt64(Double(read >= old.read ? read - old.read : 0) / dt)
                        self.diskWrite = UInt64(Double(write >= old.write ? write - old.write : 0) / dt)
                    }
                    self.previousDisk = (read, write, now)
                } else {
                    self.previousDisk = nil
                    self.diskRead = nil
                    self.diskWrite = nil
                }
            }
        }
    }

    private func updateCPU() {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ints in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ints, &count)
            }
        }
        if result == KERN_SUCCESS {
            let ticks: [UInt64] = [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1),
                                   UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
            if let old = previousTicks {
                var deltas: [UInt64] = []
                let counterRange: UInt64 = UInt64(UInt32.max) + 1
                for (current, before) in zip(ticks, old) {
                    let delta: UInt64
                    if current >= before {
                        delta = current - before
                    } else {
                        delta = (counterRange - before) + current
                    }
                    deltas.append(delta)
                }
                let total: UInt64 = deltas.reduce(0, +)
                if total > 0 { cpuPercent = 100 * Double(total - deltas[2]) / Double(total) }
            }
            previousTicks = ticks
        }
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) >= 1 { loadAverage = load[0] }
    }

    private func updateMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ints in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, ints, &count)
            }
        }
        if result == KERN_SUCCESS {
            var size: vm_size_t = 0
            if host_page_size(mach_host_self(), &size) == KERN_SUCCESS {
                // Active + wired + compressed, excluding reclaimable inactive cache.
                let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) +
                                UInt64(stats.compressor_page_count)
                memoryUsed = min(memoryTotal, usedPages * UInt64(size))
            }
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = swap.xsu_used
        }
    }

    private func updateNetwork() {
        var start: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&start) == 0, let first = start else { return }
        defer { freeifaddrs(start) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var tunnelRX: UInt64 = 0
        var tunnelTX: UInt64 = 0
        var sawPhysical = false
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let p = pointer {
            let interface = p.pointee
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let opaque = interface.ifa_data {
                let name = String(cString: interface.ifa_name)
                let data = opaque.assumingMemoryBound(to: if_data.self).pointee
                if name.hasPrefix("en") {
                    // Avoid double-counting traffic on physical and tunnel interfaces.
                    rx += UInt64(data.ifi_ibytes)
                    tx += UInt64(data.ifi_obytes)
                    sawPhysical = true
                } else if name.hasPrefix("utun") {
                    tunnelRX += UInt64(data.ifi_ibytes)
                    tunnelTX += UInt64(data.ifi_obytes)
                }
            }
            pointer = interface.ifa_next
        }
        if !sawPhysical { rx = tunnelRX; tx = tunnelTX }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = previousNetwork, let priorTime = previousNetworkTime {
            let delta = max(0.1, now - priorTime)
            networkDown = UInt64(Double(rx >= previous.rx ? rx - previous.rx : 0) / delta)
            networkUp = UInt64(Double(tx >= previous.tx ? tx - previous.tx : 0) / delta)
        }
        previousNetwork = (rx, tx)
        previousNetworkTime = now
    }

    private func updateDisk() {
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = values[.systemSize] as? NSNumber,
              let free = values[.systemFreeSize] as? NSNumber else { return }
        diskTotal = total.uint64Value
        diskUsed = max(0, diskTotal - free.uint64Value)
    }

    var thermalDescription: String {
        switch thermalState {
        case .nominal: return "Норма"
        case .fair: return "Умеренная нагрузка"
        case .serious: return "Ограничение"
        case .critical: return "Критическое"
        @unknown default: return "—"
        }
    }

    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    static func uptimeString(_ uptime: TimeInterval) -> String {
        let minutes = Int(max(0, uptime)) / 60
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return "\(days) д. \(hours) ч." }
        if hours > 0 { return "\(hours) ч. \(minutes % 60) мин." }
        return "\(minutes) мин."
    }
}
