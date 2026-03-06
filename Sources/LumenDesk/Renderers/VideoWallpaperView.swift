import AVFoundation
import AppKit
import SwiftUI

struct VideoWallpaperView: NSViewRepresentable {
    let url: URL
    let isPaused: Bool
    let muted: Bool
    let volume: Double
    let playbackRate: Double
    let scaleMode: ScaleMode

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        context.coordinator.attach(to: view)
        context.coordinator.configure(with: url)
        context.coordinator.update(
            isPaused: isPaused,
            muted: muted,
            volume: volume,
            playbackRate: playbackRate,
            scaleMode: scaleMode
        )
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.configure(with: url)
        context.coordinator.update(
            isPaused: isPaused,
            muted: muted,
            volume: volume,
            playbackRate: playbackRate,
            scaleMode: scaleMode
        )
    }

    static func dismantleNSView(_ nsView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var currentURL: URL?
        private weak var container: PlayerContainerView?

        func attach(to container: PlayerContainerView) {
            self.container = container
            container.playerLayer.player = player
        }

        func configure(with url: URL) {
            guard currentURL != url else { return }
            currentURL = url

            let asset = AVAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            player.removeAllItems()
            looper = AVPlayerLooper(player: player, templateItem: item)
        }

        func update(
            isPaused: Bool,
            muted: Bool,
            volume: Double,
            playbackRate: Double,
            scaleMode: ScaleMode
        ) {
            player.isMuted = muted
            player.volume = Float(max(0, min(volume, 1)))
            container?.playerLayer.videoGravity = scaleMode.videoGravity

            let clampedRate = Float(max(0.1, min(playbackRate, 2.0)))
            if isPaused {
                player.pause()
            } else {
                player.playImmediately(atRate: clampedRate)
            }
        }

        func teardown() {
            player.pause()
            player.removeAllItems()
            looper = nil
            currentURL = nil
            container?.playerLayer.player = nil
        }
    }
}

@MainActor
final class PlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private extension ScaleMode {
    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill:
            return .resizeAspectFill
        case .fit:
            return .resizeAspect
        case .stretch:
            return .resize
        }
    }
}
