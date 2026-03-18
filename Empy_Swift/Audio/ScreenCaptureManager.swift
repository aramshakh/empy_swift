import Foundation
import ScreenCaptureKit
import AVFoundation
import os.log

/// Manages system audio capture via ScreenCaptureKit
/// Ported from empy-trone/Recorder.swift lines 601-726
final class ScreenCaptureManager: NSObject {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "ai.empy.swift", category: "ScreenCapture")
    
    private var stream: SCStream?
    private var availableContent: SCShareableContent?
    
    /// Callback when system audio buffer is received
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    
    /// Whether system audio capture is active
    private(set) var isCapturing = false
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Request screen recording permission
    func requestPermissions() async throws -> Bool {
        let canCapture = CGPreflightScreenCaptureAccess()
        
        if !canCapture {
            CGRequestScreenCaptureAccess()
            throw ScreenCaptureError.permissionDenied
        }
        
        return true
    }
    
    /// Update available content (windows/displays)
    func updateAvailableContent() async throws {
        logger.info("Fetching available screen content...")
        
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        
        availableContent = content
        logger.info("Available content updated: \\(content.displays.count) displays, \\(content.windows.count) windows")
    }
    
    /// Start capturing system audio
    func startCapture() async throws {
        guard !isCapturing else {
            logger.warning("Already capturing")
            return
        }
        
        // Update available content if not already loaded
        if availableContent == nil {
            try await updateAvailableContent()
        }
        
        // Create stream configuration
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = Int(AudioConstants.sampleRate)
        config.channelCount = AudioConstants.channelCount
        config.excludesCurrentProcessAudio = true // Don't capture our own app
        
        // Create content filter (captures all system audio)
        // Using nil filter captures all audio regardless of window
        let filter = SCContentFilter(desktopIndependentWindow: nil)
        
        // Create stream
        stream = SCStream(
            filter: filter,
            configuration: config,
            delegate: self
        )
        
        // Add audio output handler
        try stream?.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: .global(qos: .userInitiated)
        )
        
        // Start capture
        try await stream?.startCapture()
        
        isCapturing = true
        logger.info("System audio capture started")
    }
    
    /// Stop capturing system audio
    func stopCapture() async throws {
        guard isCapturing else {
            logger.warning("Not currently capturing")
            return
        }
        
        try await stream?.stopCapture()
        stream = nil
        isCapturing = false
        
        logger.info("System audio capture stopped")
    }
    
    // MARK: - Private Helpers
    
    /// Convert CMSampleBuffer to AVAudioPCMBuffer
    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            logger.error("Failed to get format description")
            return nil
        }
        
        guard let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            logger.error("Failed to get audio stream description")
            return nil
        }
        
        guard let format = AVAudioFormat(streamDescription: audioStreamBasicDescription) else {
            logger.error("Failed to create AVAudioFormat")
            return nil
        }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            logger.error("Failed to get data buffer")
            return nil
        }
        
        var lengthAtOffset: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: nil,
            dataPointerOut: &dataPointer
        )
        
        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            logger.error("Failed to get data pointer")
            return nil
        }
        
        let frameCount = AVAudioFrameCount(lengthAtOffset) / format.streamDescription.pointee.mBytesPerFrame
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            logger.error("Failed to create PCM buffer")
            return nil
        }
        
        buffer.frameLength = frameCount
        
        // Copy audio data
        let bytesToCopy = Int(lengthAtOffset)
        let dest = buffer.audioBufferList.pointee.mBuffers.mData
        memcpy(dest, data, bytesToCopy)
        
        return buffer
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("ScreenCaptureKit stopped with error: \\(error.localizedDescription)")
        isCapturing = false
        
        // TODO: Implement reconnection logic
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        // Only process audio samples
        guard outputType == .audio else { return }
        
        // Convert to PCM buffer
        guard let pcmBuffer = createPCMBuffer(from: sampleBuffer) else {
            logger.error("Failed to convert sample buffer to PCM buffer")
            return
        }
        
        // Deliver to callback
        onAudioBuffer?(pcmBuffer)
    }
}

// MARK: - Errors

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noContentAvailable
    case streamCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission denied. Please enable in System Settings > Privacy & Security > Screen Recording."
        case .noContentAvailable:
            return "No screen content available for capture"
        case .streamCreationFailed:
            return "Failed to create screen capture stream"
        }
    }
}
