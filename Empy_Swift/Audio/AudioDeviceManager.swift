//
//  AudioDeviceManager.swift
//  Empy_Swift
//
//  CoreAudio wrapper that enumerates audio devices, observes hardware changes,
//  and sets the input device on an AVAudioEngine instance.
//

import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import Combine

/// Singleton that owns all CoreAudio device management.
///
/// Usage:
///   AudioDeviceManager.shared.inputDevices   // observed by SwiftUI
///   AudioDeviceManager.shared.setInputDevice(device, on: engine)
///   AudioDeviceManager.shared.resolveDevice(uid: "UID-string")
final class AudioDeviceManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AudioDeviceManager()

    // MARK: - Published state

    @Published private(set) var inputDevices:  [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []

    // MARK: - Private

    private var hardwareListenerAdded = false

    // MARK: - Init

    private init() {
        refreshDevices()
        addHardwareListener()
    }

    // MARK: - Public API

    /// Set the input device on a running AVAudioEngine.
    /// Must be called after `engine.start()`.
    @discardableResult
    func setInputDevice(_ device: AudioDevice, on engine: AVAudioEngine) throws -> Bool {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw AudioDeviceError.noAudioUnit
        }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioDeviceError.failedToSetDevice(status)
        }
        return true
    }

    /// Find an AudioDevice by its persistent UID.
    func resolveDevice(uid: String) -> AudioDevice? {
        return (inputDevices + outputDevices).first { $0.uid == uid }
    }

    /// Set the macOS system default output device.
    /// SCKit captures audio routed to the default output, so this affects which device's audio is captured.
    func setSystemDefaultOutputDevice(_ device: AudioDevice) throws {
        var deviceID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        guard status == noErr else {
            throw AudioDeviceError.failedToSetDevice(status)
        }
    }

    /// The current system default input device ID.
    var systemDefaultInputID: AudioDeviceID {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    // MARK: - Enumeration

    func refreshDevices() {
        let all = enumerateAllDevices()
        DispatchQueue.main.async {
            self.inputDevices  = all.filter { $0.hasInput }
            self.outputDevices = all.filter { $0.hasOutput }
        }
    }

    private func enumerateAllDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { buildDevice(id: $0) }
    }

    private func buildDevice(id: AudioDeviceID) -> AudioDevice? {
        guard let name = deviceName(id: id),
              let uid  = deviceUID(id: id) else { return nil }

        let inputCh  = channelCount(id: id, scope: kAudioDevicePropertyScopeInput)
        let outputCh = channelCount(id: id, scope: kAudioDevicePropertyScopeOutput)

        // Skip devices with no channels at all (e.g. aggregate sub-devices)
        guard inputCh > 0 || outputCh > 0 else { return nil }

        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            hasInput:  inputCh > 0,
            hasOutput: outputCh > 0,
            inputChannelCount:  inputCh,
            outputChannelCount: outputCh
        )
    }

    // MARK: - CoreAudio property helpers

    private func deviceName(id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.size)
        var nameRef: Unmanaged<CFString>? = nil
        guard withUnsafeMutablePointer(to: &nameRef, {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer($0))
        }) == noErr, let ref = nameRef else { return nil }
        return ref.takeRetainedValue() as String
    }

    private func deviceUID(id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.size)
        var uidRef: Unmanaged<CFString>? = nil
        guard withUnsafeMutablePointer(to: &uidRef, {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer($0))
        }) == noErr, let ref = uidRef else { return nil }
        return ref.takeRetainedValue() as String
    }

    private func channelCount(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return 0 }

        let bufferListSize = Int(dataSize)
        let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferListSize,
                                                         alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawBuffer.deallocate() }

        guard AudioObjectGetPropertyData(
            id, &address, 0, nil, &dataSize,
            rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        ) == noErr else { return 0 }

        let bufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self).pointee
        let numBuffers = Int(bufferList.mNumberBuffers)

        // AudioBufferList stores buffers in a flexible array after mNumberBuffers
        return withUnsafeBytes(of: bufferList) { ptr -> Int in
            var total = 0
            let base = ptr.baseAddress!
                .advanced(by: MemoryLayout<UInt32>.size) // skip mNumberBuffers
                .assumingMemoryBound(to: AudioBuffer.self)
            for i in 0..<numBuffers {
                total += Int(base[i].mNumberChannels)
            }
            return total
        }
    }

    // MARK: - Hardware change listener

    private func addHardwareListener() {
        guard !hardwareListenerAdded else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }
        hardwareListenerAdded = true
    }
}
