//
//  CallDetector.swift
//  Empy_Swift
//
//  Detects when the user is on a call using two signals:
//  1. Mic is being used by another process (CoreAudio kAudioDevicePropertyDeviceIsRunningSomewhere)
//  2. There is actual audio activity on the mic (VAD via RMS threshold)
//
//  Both signals must be true simultaneously before firing onCallDetected.
//

import Foundation
import AVFoundation
import CoreAudio
import Combine

final class CallDetector: ObservableObject {

    /// Fired on the main thread when both mic-busy + voice-activity are detected.
    var onCallDetected: (() -> Void)?

    /// True while actively monitoring.
    @Published private(set) var isMonitoring = false

    // MARK: - Configuration

    /// RMS threshold above which audio is considered voice activity (0.0 – 1.0).
    private let vadThreshold: Float = 0.02

    /// How long voice activity must be sustained before firing (avoids one-shot noise triggers).
    private let voiceActivityDuration: TimeInterval = 2.0

    // MARK: - State

    private var tapEngine: AVAudioEngine?
    private var voiceStartTime: Date?
    private var hasFired = false

    // CoreAudio listener
    private var monitoredDeviceID: AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var propertyListenerAdded = false

    // MARK: - Public API

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        hasFired = false
        voiceStartTime = nil
        startMicTap()
        startDeviceBusyListener()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        hasFired = false
        voiceStartTime = nil
        stopMicTap()
        stopDeviceBusyListener()
    }

    // MARK: - Mic TAP (VAD)

    private func startMicTap() {
        let engine = AVAudioEngine()
        tapEngine = engine

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let rms = self.rms(buffer: buffer)
            self.handleVAD(rms: rms)
        }

        do {
            try engine.start()
        } catch {
            print("⚠️ CallDetector: tap engine start failed — \(error.localizedDescription)")
            tapEngine = nil
        }
    }

    private func stopMicTap() {
        tapEngine?.inputNode.removeTap(onBus: 0)
        tapEngine?.stop()
        tapEngine = nil
    }

    private func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return sqrt(sum / Float(count))
    }

    private func handleVAD(rms: Float) {
        if rms >= vadThreshold {
            if voiceStartTime == nil {
                voiceStartTime = Date()
            } else if let start = voiceStartTime,
                      Date().timeIntervalSince(start) >= voiceActivityDuration {
                checkAndFire()
            }
        } else {
            voiceStartTime = nil
        }
    }

    // MARK: - CoreAudio device-busy listener

    private func startDeviceBusyListener() {
        monitoredDeviceID = defaultInputDeviceID()
        guard monitoredDeviceID != kAudioObjectUnknown else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListener(monitoredDeviceID, &address, deviceBusyCallback, selfPtr)

        if status == noErr {
            propertyListenerAdded = true
        } else {
            print("⚠️ CallDetector: failed to add device busy listener (status \(status))")
        }
    }

    private func stopDeviceBusyListener() {
        guard propertyListenerAdded, monitoredDeviceID != kAudioObjectUnknown else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(monitoredDeviceID, &address, deviceBusyCallback, selfPtr)
        propertyListenerAdded = false
    }

    /// Returns true if the input device is currently in use by any process.
    var isMicBusyByOtherApp: Bool {
        guard monitoredDeviceID != kAudioObjectUnknown else { return false }
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(monitoredDeviceID, &address, 0, nil, &size, &isRunning)
        return isRunning != 0
    }

    // MARK: - Fire

    private func checkAndFire() {
        guard !hasFired, isMicBusyByOtherApp else { return }
        hasFired = true
        DispatchQueue.main.async { [weak self] in
            self?.onCallDetected?()
        }
    }

    // Called by CallNotificationManager after cooldown expires — allows re-detection.
    func resetFired() {
        hasFired = false
        voiceStartTime = nil
    }

    // MARK: - Helpers

    private func defaultInputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioObjectSystemObject)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }
}

// MARK: - CoreAudio C callback (must be a free function)

private func deviceBusyCallback(
    objectID: AudioObjectID,
    numAddresses: UInt32,
    addresses: UnsafePointer<AudioObjectPropertyAddress>,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    // We don't act directly here — VAD + busy check happens together in checkAndFire.
    // The callback just tells us the property changed; the tap callback does the real logic.
    return noErr
}
