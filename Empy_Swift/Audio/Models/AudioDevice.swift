//
//  AudioDevice.swift
//  Empy_Swift
//
//  Value type representing a single macOS audio device.
//

import Foundation
import CoreAudio

/// Represents a macOS audio input or output device.
struct AudioDevice: Identifiable, Hashable {
    /// CoreAudio device ID (volatile — changes if device is replugged)
    let id: AudioDeviceID

    /// Stable UID from kAudioDevicePropertyDeviceUID — persists across reboots
    let uid: String

    /// Human-readable name, e.g. "MacBook Pro Microphone" or "AirPods Pro"
    let name: String

    /// True if the device has at least one input channel
    let hasInput: Bool

    /// True if the device has at least one output channel
    let hasOutput: Bool

    /// Number of input channels (0 for output-only devices)
    let inputChannelCount: Int

    /// Number of output channels (0 for input-only devices)
    let outputChannelCount: Int
}
