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
    func requestPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            if CGPreflightScreenCaptureAccess() {
                return true
            }
            return await CGRequestScreenCaptureAccess()
        } else {
            // macOS 13: Permission dialog appears on first capture attempt
            return true
        }
    }
    
    /// Start capturing system audio
    /// - Throws: Permission errors or ScreenCaptureKit errors
    func start() async throws {
        // Check permission
        guard await requestPermission() else {
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
        
        // Create content filter (capture all system audio)
        let content = try await SCShareableContent.current
        
        // Filter: desktop-wide audio (no specific window)
        guard let firstWindow = content.windows.first else {
            throw SystemAudioError.noWindowsAvailable
        }
        let filter = SCContentFilter(desktopIndependentWindow: firstWindow)
        
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
    
    /// Convert CMSampleBuffer to AVAudioPCMBuffer
    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        // Get audio format description
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("⚠️ No format description in sample buffer")
            return nil
        }
        
        // Get audio stream basic description
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            print("⚠️ No stream basic description")
            return nil
        }
        
        // Create AVAudioFormat from ASBD
        var mutableAsbd = asbd
        guard let format = AVAudioFormat(streamDescription: &mutableAsbd) else {
            print("⚠️ Failed to create AVAudioFormat")
            return nil
        }
        
        // Get block buffer containing audio data
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("⚠️ No data buffer in sample buffer")
            return nil
        }
        
        // Get data pointer
        var dataPointer: UnsafeMutablePointer<Int8>?
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        guard status == kCMBlockBufferNoErr, let pointer = dataPointer else {
            print("⚠️ Failed to get data pointer: \(status)")
            return nil
        }
        
        // Calculate frame count
        let bytesPerFrame = UInt32(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else {
            print("⚠️ Invalid bytes per frame: \(bytesPerFrame)")
            return nil
        }
        
        let frameCount = AVAudioFrameCount(lengthAtOffset) / bytesPerFrame
        
        // Create PCM buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("⚠️ Failed to create PCM buffer")
            return nil
        }
        
        buffer.frameLength = frameCount
        
        // Copy audio data
        if let bufferData = buffer.audioBufferList.pointee.mBuffers.mData {
            memcpy(bufferData, pointer, lengthAtOffset)
        }
        
        return buffer
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
    case noWindowsAvailable
    case permissionDenied
    case streamCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .noWindowsAvailable:
            return "No windows available for screen capture"
        case .permissionDenied:
            return "Screen recording permission denied"
        case .streamCreationFailed:
            return "Failed to create screen capture stream"
        }
    }
}
