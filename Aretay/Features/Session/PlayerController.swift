//
//  PlayerController.swift
//  Aretay
//
//  MainActor AVPlayer wrapper for feed pages: publishes playback time (for
//  the caption overlay), completion (to auto-advance the feed), and load
//  failure (to fall back to the script card), and renders through a bare
//  AVPlayerLayer — no system controls. Question clips can loop; the first
//  pass plays with audio, every repeat is muted.
//

import AVFoundation
import Observation
import SwiftUI

@MainActor
@Observable
final class PlayerController {
    let player = AVPlayer()
    private(set) var currentTimeMs: Double = 0
    private(set) var didFinish = false
    /// True when the item can't load (bad URL, no network, private bucket).
    /// Pages must fall back to non-video content or the feed would stall.
    private(set) var didFail = false

    private var loops = false
    private var loadedURL: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusWatch: Task<Void, Never>?

    init() {
        player.preventsDisplaySleepDuringVideoPlayback = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func load(url: URL, autoplay: Bool = true, loop: Bool = false) {
        // Re-activating the same page resumes instead of reloading.
        if loadedURL == url, !didFail {
            loops = loop
            if autoplay { player.play() }
            return
        }

        teardownObservers()
        didFinish = false
        didFail = false
        currentTimeMs = 0
        loops = loop
        loadedURL = url
        player.isMuted = false

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        statusWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let item = self?.player.currentItem else { return }
                if item.status == .failed {
                    self?.didFail = true
                    return
                }
                if item.status == .readyToPlay { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTimeMs = time.seconds * 1000
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.loops {
                    // The narration already played once — repeats are silent.
                    self.player.isMuted = true
                    self.player.seek(to: .zero)
                    self.player.play()
                } else {
                    self.didFinish = true
                }
            }
        }

        if autoplay {
            player.play()
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func replay() {
        didFinish = false
        player.seek(to: .zero)
        player.play()
    }

    func stop() {
        player.pause()
        teardownObservers()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
    }

    private func teardownObservers() {
        statusWatch?.cancel()
        statusWatch = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

/// Full-bleed video layer (aspect-fill, like the 9:16 source).
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
