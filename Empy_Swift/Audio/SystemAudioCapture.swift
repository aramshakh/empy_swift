//
//  SystemAudioCapture.swift
//  Empy_Swift
//
//  T04: System audio capture via ScreenCaptureKit
//  Captures system audio (Zoom/Meet/YouTube) separately from microphone
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

/// Delegate for system audio capture events
protocol SystemAudioCaptureDelegate: AnyObject {
    /// Called when a system audio buffer is ready
    func systemAudioDidCapture(buffer: AVAudioPCMBuffer)
    
    /// Called when system audio capture fails
    func systemAudioDidFail(error: Error)
}

/// System audio capture using ScreenCaptureKit
/// 
/// **Requirements:**
/// - macOS 13.0+ (ScreenCaptureKit availability)
/// - Screen recording permission granted
/// - Captures system-wide audio (excludes current process)
class SystemAudioCapture: NSObject {
    weak var delegate: SystemAudioCaptureDelegate?
    
    private var stream: SCStream?
    private let logger: SessionLogger
    
    /// Target audio format: 48kHz, stereo, Float32
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )
    
    /// Permission status for screen recording
    var hasPermission: Bool {
        if #available(macOS 14.0, *) {
            return CGPreflightScreenCaptureAccess()
        } else {
            // On macOS 13, permission is granted implicitly on first use
            return true
        }
    }
    
    init(logger: SessionLogger = .shared) {
        self.logger = logger
        super.init()
    }
    
    /// Request screen recording permission
    /// - Returns: True if permission granted or already available
    @discardableResult
    func requestPermission() -> Bool {
        guard #available(macOS 14.0, *) else {
            // macOS 13: permission dialog appears on first capture attempt
            return true
        }
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }
    
    /// Start capturing system audio
    /// - Throws: Permission errors or ScreenCaptureKit errors
    func start() async throws {
        // Check permission
        guard requestPermission() else {
            logger.log(event: "system_audio_permission_denied", layer: "audio")
            throw NSError(
                domain: "SystemAudioCapture",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Screen recording permission denied"]
            )
        }
        
        logger.log(
            event: "system_audio_setup",
            layer: "audio",
            details: [
                "sample_rate": "48000",
                "channels": "2",
                "format": "Float32"
            ]
        )
        
        // Create content filter: capture ALL audio from the main display.
        // Using desktopIndependentWindow was wrong — it only captures audio from
        // one specific window. The display-level filter captures all system audio.
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: false)
        
        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplayAvailable
        }
        
        // Exclude current app (prevent feedback), include all other applications.
        let excludedApps = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: excludedApps,
                                     exceptingWindows: [])
        
        // Configure stream
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        
        // Exclude audio from this app (prevent feedback loop)
        config.excludesCurrentProcessAudio = true
        
        // Minimum frame interval for audio
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        
        // Create stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Add audio output handler
        try stream.addStreamOutput(
            self,
            type: SCStreamOutputType.audio,
            sampleHandlerQueue: DispatchQueue(
                label: "com.empy.systemAudio",
                qos: .userInitiated
            )
        )
        
        // Start capture
        try await stream.startCapture()
        
        self.stream = stream
        
        logger.log(event: "system_audio_started", layer: "audio")
        print("✅ System audio capture started")
    }
    
    /// Stop capturing system audio
    func stop() async {
        guard let stream = stream else { return }
        
        do {
            try await stream.stopCapture()
            self.stream = nil
            
            logger.log(event: "system_audio_stopped", layer: "audio")
            print("🛑 System audio capture stopped")
        } catch {
            logger.log(
                event: "system_audio_stop_failed",
                layer: "audio",
                details: ["error": error.localizedDescription]
            )
        }
    }
    
    /// Convert CMSampleBuffer to AVAudioPCMBuffer using Apple's recommended approach.
    ///
    /// Uses `withAudioBufferList` + `AVAudioPCMBuffer(pcmFormat:bufferListNoCopy:)`
    /// which correctly handles non-interleaved multi-channel audio from SCKit.
    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        var result: AVAudioPCMBuffer?
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
                guard
                    let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                    let format = AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate,
                                              channels: description.mChannelsPerFrame),
                    let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                                    bufferListNoCopy: audioBufferList.unsafePointer)
                else { return }
                result = pcmBuffer
            }
        } catch {
            // Sample buffer audio extraction failed — not fatal, just skip this buffer
        }
        return result
    }
}

// MARK: - SCStreamDelegate
extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.log(
            event: "system_audio_stream_error",
            layer: "audio",
            details: ["error": error.localizedDescription]
        )
        
        delegate?.systemAudioDidFail(error: error)
    }
}

// MARK: - SCStreamOutput
extension SystemAudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio samples
        guard type == .audio else { return }
        
        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let pcmBuffer = createPCMBuffer(from: sampleBuffer) else {
            return
        }
        
        // Notify delegate
        delegate?.systemAudioDidCapture(buffer: pcmBuffer)
    }
}

// MARK: - Error Types
enum SystemAudioError: LocalizedError {
    case noDisplayAvailable
    case permissionDenied
    case streamCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display available for system audio capture"
        case .permissionDenied:
            return "Screen recording permission denied"
        case .streamCreationFailed:
            return "Failed to create screen capture stream"
        }
    }
}
