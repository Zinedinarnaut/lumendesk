import Darwin
import Foundation

@MainActor
final class CPULoadMonitor: ObservableObject {
    @Published private(set) var systemUsage: Double = 0
    @Published private(set) var throttleFactor: Double = 1.0

    private var timer: Timer?
    private var previousSample: host_cpu_load_info_data_t?

    func start() {
        if timer != nil {
            return
        }

        sample()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousSample = nil
        systemUsage = 0
        throttleFactor = 1.0
    }

    private func sample() {
        guard let current = readCPUInfo() else {
            return
        }

        defer {
            previousSample = current
        }

        guard let previous = previousSample else {
            return
        }

        let deltaUser = Double(tick(current, CPU_STATE_USER) - tick(previous, CPU_STATE_USER))
        let deltaSystem = Double(tick(current, CPU_STATE_SYSTEM) - tick(previous, CPU_STATE_SYSTEM))
        let deltaIdle = Double(tick(current, CPU_STATE_IDLE) - tick(previous, CPU_STATE_IDLE))
        let deltaNice = Double(tick(current, CPU_STATE_NICE) - tick(previous, CPU_STATE_NICE))

        let deltaTotal = max(1, deltaUser + deltaSystem + deltaIdle + deltaNice)
        let usage = (deltaUser + deltaSystem + deltaNice) / deltaTotal

        systemUsage = max(0, min(usage, 1.0))
        throttleFactor = Self.throttleFactor(for: systemUsage)
    }

    private func readCPUInfo() -> host_cpu_load_info_data_t? {
        var info = host_cpu_load_info_data_t()
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &size)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return info
    }

    private func tick(_ info: host_cpu_load_info_data_t, _ state: Int32) -> UInt32 {
        withUnsafePointer(to: info.cpu_ticks) { pointer in
            pointer.withMemoryRebound(to: UInt32.self, capacity: Int(CPU_STATE_MAX)) { rebound in
                rebound[Int(state)]
            }
        }
    }

    private static func throttleFactor(for usage: Double) -> Double {
        switch usage {
        case 0.95...:
            return 0.3
        case 0.88..<0.95:
            return 0.45
        case 0.80..<0.88:
            return 0.6
        case 0.72..<0.80:
            return 0.75
        default:
            return 1.0
        }
    }
}
