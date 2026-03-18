//
//  SpeakerTester.swift
//  Empy_Swift
//
//  Plays the bundled test_tone.wav through the system default output.
//

import Foundation
import AVFoundation
import Combine

final class SpeakerTester: NSObject, ObservableObject {
    @Published private(set) var isPlaying: Bool = false

    private var player: AVAudioPlayer?

    func playTestSound() {
        guard !isPlaying else { return }

        guard let url = Bundle.main.url(forResource: "test_tone", withExtension: "wav") else {
            print("⚠️ SpeakerTester: test_tone.wav not found in bundle")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            isPlaying = true
        } catch {
            print("⚠️ SpeakerTester: playback failed — \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}

// MARK: - AVAudioPlayerDelegate

extension SpeakerTester: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.player = nil
        }
    }
}
