import AVFoundation
import Foundation
import os

@MainActor
final class RestBellPlayer {
    private var player: AVAudioPlayer?
    private var sessionConfigured = false

    init(bundle: Bundle = .main) {
        configureSessionIfNeeded()
        loadPlayer(from: bundle)
    }

    func play() {
        guard let player else {
            Log.workout.warning("rest bell missing from bundle")
            return
        }
        configureSessionIfNeeded()
        player.currentTime = 0
        player.play()
        Log.workout.info("rest bell played")
        scheduleSessionDeactivation(after: player.duration)
    }

    private func scheduleSessionDeactivation(after duration: TimeInterval) {
        let delay = max(duration, 0.5) + 0.25
        Task {
            try? await Task.sleep(for: .seconds(delay))
            deactivateSessionIfIdle()
        }
    }

    private func deactivateSessionIfIdle() {
        guard sessionConfigured else { return }
        guard player?.isPlaying != true else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            sessionConfigured = false
            Log.workout.info("rest bell audio session deactivated")
        } catch {
            Log.workout.error(
                "rest bell audio session deactivate failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            sessionConfigured = true
        } catch {
            Log.workout.error("rest bell audio session failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadPlayer(from bundle: Bundle) {
        let extensions = ["caf", "wav"]
        for ext in extensions {
            guard let url = bundle.url(forResource: "RestBell", withExtension: ext) else { continue }
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                Log.workout.info("rest bell loaded extension=\(ext, privacy: .public)")
                return
            } catch {
                Log.workout.error("rest bell load failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
