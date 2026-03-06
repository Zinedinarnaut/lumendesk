import AVFoundation
import Foundation

@MainActor
final class AudioReactiveService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var level: Double = 0
    @Published private(set) var beatPulse: Double = 0
    @Published private(set) var lastBeatDate: Date?
    @Published private(set) var statusMessage: String?

    private let engine = AVAudioEngine()
    private var decayTimer: Timer?
    private var levelHistory: [Double] = []
    private var lastBeatTimestamp: TimeInterval = 0

    private var isEnabled = false
    private var sensitivity: Double = 1.0

    func updateConfiguration(enabled: Bool, sensitivity: Double) {
        self.sensitivity = max(0.5, min(sensitivity, 2.0))

        guard enabled != isEnabled else {
            return
        }

        isEnabled = enabled

        if enabled {
            startIfAuthorized()
        } else {
            stop()
        }
    }

    private func startIfAuthorized() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.start()
                    } else {
                        self.permissionDenied = true
                        self.statusMessage = "Microphone permission denied"
                        self.stop()
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
            statusMessage = "Enable microphone access in System Settings for music reactive mode"
            stop()
        @unknown default:
            stop()
        }
    }

    private func start() {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        if format.sampleRate == 0 || format.channelCount == 0 {
            statusMessage = "No audio input device available"
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            isRunning = true
            permissionDenied = false
            statusMessage = nil
            startDecayTimer()
        } catch {
            statusMessage = "Could not start audio engine: \(error.localizedDescription)"
            stop()
        }
    }

    private func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        beatPulse = 0
        level = 0
        levelHistory.removeAll(keepingCapacity: false)
        decayTimer?.invalidate()
        decayTimer = nil
    }

    private func startDecayTimer() {
        decayTimer?.invalidate()
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.beatPulse *= 0.88
                if self.beatPulse < 0.01 {
                    self.beatPulse = 0
                }
            }
        }
        RunLoop.main.add(decayTimer!, forMode: .common)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return }

        var sumSquares = 0.0
        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for sampleIndex in 0..<frameCount {
                let sample = Double(channel[sampleIndex])
                sumSquares += sample * sample
            }
        }

        let meanSquare = sumSquares / Double(frameCount * channelCount)
        let rms = sqrt(meanSquare)
        let normalized = min(1.0, max(0.0, rms * 22.0))

        Task { @MainActor in
            self.consume(normalizedLevel: normalized)
        }
    }

    private func consume(normalizedLevel: Double) {
        level = (level * 0.82) + (normalizedLevel * 0.18)

        levelHistory.append(level)
        if levelHistory.count > 45 {
            levelHistory.removeFirst(levelHistory.count - 45)
        }

        let average = levelHistory.reduce(0, +) / Double(max(levelHistory.count, 1))
        let thresholdMultiplier = max(1.08, 1.72 - (0.45 * sensitivity))
        let threshold = max(0.05, average * thresholdMultiplier)
        let now = CACurrentMediaTime()

        if level > threshold, now - lastBeatTimestamp > 0.16 {
            lastBeatTimestamp = now
            beatPulse = 1.0
            lastBeatDate = Date()
        }
    }
}
