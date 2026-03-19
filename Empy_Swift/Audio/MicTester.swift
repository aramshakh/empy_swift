//
//  MicTester.swift
//  Empy_Swift
//
//  Records 3 seconds from the selected input device, then plays it back.
//  Uses a separate AVAudioEngine — never touches the session audio pipeline.
//

import Foundation
import AVFoundation
import Combine

enum MicTestState: Equatable {
    case idle
    case recording(progress: Double)  // 0.0 ... 1.0
    case playing(progress: Double)
}

final class MicTester: ObservableObject {
    @Published private(set) var state: MicTestState = .idle
    /// Normalised RMS level (0...1) — updated 10× per second during recording
    @Published private(set) var level: Float = 0

    private let recordDuration: TimeInterval = 3.0

    private var recordEngine: AVAudioEngine?
    private var recordedBuffers: [AVAudioPCMBuffer] = []
    private var recordFormat: AVAudioFormat?
    private var progressTimer: Timer?
    private var recordStart: Date?

    // MARK: - Public

    func startTest(device: AudioDevice?) {
        guard state == .idle else { return }
        recordedBuffers = []
        level = 0
        startRecording(device: device)
    }

    func cancel() {
        stopAll()
        state = .idle
    }

    // MARK: - Recording

    private func startRecording(device: AudioDevice?) {
        let engine = AVAudioEngine()
        recordEngine = engine

        // Start engine first — audioUnit is only available after engine.start()
        do {
            try engine.start()
        } catch {
            print("⚠️ MicTester: engine start failed — \(error.localizedDescription)")
            state = .idle
            return
        }

        // Apply device after engine is running so audioUnit is initialised
        if let device = device {
            do {
                try AudioDeviceManager.shared.setInputDevice(device, on: engine)
            } catch {
                print("⚠️ MicTester: failed to set input device — \(error.localizedDescription)")
                // Non-fatal: recording continues on system default
            }
        }

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        recordFormat = inputFormat

        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Store buffer (copy because AVAudioEngine may reuse the backing store)
            if let copy = self.copyBuffer(buffer) {
                self.recordedBuffers.append(copy)
            }
            // RMS level for the meter
            let rms = self.rms(buffer: buffer)
            DispatchQueue.main.async { self.level = rms }
        }

        recordStart = Date()
        DispatchQueue.main.async { self.state = .recording(progress: 0) }

        // Use RunLoop.main with .common so the timer fires even during UI tracking loops
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.recordStart else { return }
            let elapsed = Date().timeIntervalSince(start)
            let progress = min(elapsed / self.recordDuration, 1.0)
            DispatchQueue.main.async { self.state = .recording(progress: progress) }
            if elapsed >= self.recordDuration {
                self.finishRecordingAndPlayBack()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func finishRecordingAndPlayBack() {
        progressTimer?.invalidate()
        progressTimer = nil

        guard let engine = recordEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recordEngine = nil

        guard !recordedBuffers.isEmpty,
              let format = recordFormat else {
            state = .idle
            return
        }

        startPlayback(buffers: recordedBuffers, format: format)
    }

    // MARK: - Playback

    private func startPlayback(buffers: [AVAudioPCMBuffer], format: AVAudioFormat) {
        let engine = AVAudioEngine()
        let player  = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("⚠️ MicTester: playback engine start failed — \(error.localizedDescription)")
            state = .idle
            return
        }

        // Schedule all recorded buffers
        for (i, buf) in buffers.enumerated() {
            let isLast = (i == buffers.count - 1)
            if isLast {
                player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.stopAll()
                        self?.state = .idle
                    }
                }
            } else {
                player.scheduleBuffer(buf)
            }
        }

        player.play()

        let totalFrames = buffers.reduce(0) { $0 + Double($1.frameLength) }
        let playbackDuration = totalFrames / format.sampleRate

        DispatchQueue.main.async { self.state = .playing(progress: 0) }
        let playStart = Date()
        let playTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let elapsed = Date().timeIntervalSince(playStart)
            let progress = min(elapsed / playbackDuration, 1.0)
            DispatchQueue.main.async { self.state = .playing(progress: progress) }
        }
        RunLoop.main.add(playTimer, forMode: .common)
        progressTimer = playTimer

        // Keep strong references for the duration of playback
        objc_setAssociatedObject(self, &MicTester.playbackEngineKey, engine, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(self, &MicTester.playbackPlayerKey, player, .OBJC_ASSOCIATION_RETAIN)
    }

    // MARK: - Helpers

    private func stopAll() {
        progressTimer?.invalidate()
        progressTimer = nil
        recordEngine?.inputNode.removeTap(onBus: 0)
        recordEngine?.stop()
        recordEngine = nil
        level = 0
        // Release associated playback objects
        objc_setAssociatedObject(self, &MicTester.playbackEngineKey, nil, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(self, &MicTester.playbackPlayerKey, nil, .OBJC_ASSOCIATION_RETAIN)
    }

    private func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return min(sqrt(sum / Float(count)) * 10, 1.0) // scale for visibility
    }

    private func copyBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: src.format,
                                          frameCapacity: src.frameLength) else { return nil }
        copy.frameLength = src.frameLength
        guard let srcPtr  = src.floatChannelData,
              let destPtr = copy.floatChannelData else { return nil }
        let channels = Int(src.format.channelCount)
        let bytes = Int(src.frameLength) * MemoryLayout<Float>.size
        for ch in 0..<channels {
            memcpy(destPtr[ch], srcPtr[ch], bytes)
        }
        return copy
    }

    // Key pointers for objc_setAssociatedObject (need stable addresses)
    private static var playbackEngineKey = 0
    private static var playbackPlayerKey = 1
}
