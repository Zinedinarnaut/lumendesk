import Foundation

@MainActor
final class AudioReactiveService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var level: Double = 0
    @Published private(set) var beatPulse: Double = 0
    @Published private(set) var lastBeatDate: Date?
    @Published private(set) var statusMessage: String?

    func updateConfiguration(enabled: Bool, sensitivity: Double) {
        if enabled {
            statusMessage = "Music reactive mode is disabled in this build."
        } else {
            statusMessage = nil
        }
        isRunning = false
        permissionDenied = false
        beatPulse = 0
        level = 0
        lastBeatDate = nil
    }
}
