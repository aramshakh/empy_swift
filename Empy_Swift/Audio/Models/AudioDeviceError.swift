//
//  AudioDeviceError.swift
//  Empy_Swift
//
//  Errors produced by AudioDeviceManager device operations.
//

import Foundation
import CoreAudio

enum AudioDeviceError: LocalizedError {
    case noAudioUnit
    case failedToSetDevice(OSStatus)
    case deviceNotFound(uid: String)
    case enumerationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noAudioUnit:
            return "Audio unit not available on engine node"
        case .failedToSetDevice(let status):
            return "Failed to set audio device (OSStatus: \(status))"
        case .deviceNotFound(let uid):
            return "Audio device not found: \(uid)"
        case .enumerationFailed(let status):
            return "Failed to enumerate audio devices (OSStatus: \(status))"
        }
    }
}
