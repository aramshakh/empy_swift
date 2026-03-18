import AVFoundation

/// Audio configuration constants ported from empy-trone/Recorder.swift
enum AudioConstants {
    // MARK: - Sample Rate & Channels
    
    /// Sample rate for all audio processing (48kHz - production quality)
    static let sampleRate: Double = 48000
    
    /// Number of audio channels (stereo)
    static let channelCount: Int = 2
    
    // MARK: - Audio Format
    
    /// Output format for file writing
    static let outputCommonFormat: AVAudioCommonFormat = .pcmFormatFloat32
    
    /// Whether output format is interleaved
    static let outputIsInterleaved: Bool = false
    
    /// Tap buffer size for real-time processing
    static let tapBufferSize: AVAudioFrameCount = 480
    
    /// Bit depth for FLAC encoding
    static let outputBitDepth: Int = 16
    
    // MARK: - Chunking
    
    /// Default chunk duration (20 seconds per file)
    static let defaultChunkDurationSeconds: TimeInterval = 20.0
    
    /// Calculated frames per chunk (at 48kHz)
    static var framesPerChunk: AVAudioFrameCount {
        AVAudioFrameCount(sampleRate * defaultChunkDurationSeconds)
    }
    
    // MARK: - Performance Monitoring
    
    /// Interval for performance metric reports
    static let performanceMonitoringInterval: TimeInterval = 60.0
    
    /// Optimal buffer processing time threshold (5ms)
    static let optimalBufferProcessingTime: TimeInterval = 0.005
    
    // MARK: - Error Recovery
    
    /// Maximum consecutive errors before recovery attempt
    static let maxConsecutiveErrors: Int = 5
    
    /// Maximum recovery attempts before giving up
    static let maxRecoveryAttempts: Int = 3
    
    /// Delay between recovery attempts
    static let errorRecoveryDelay: TimeInterval = 2.0
    
    /// Memory cleanup interval (every N chunks)
    static let memoryCleanupInterval: Int = 10
    
    // MARK: - Helpers
    
    /// Standard output format for file writing
    static var standardOutputFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: outputCommonFormat,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: outputIsInterleaved
        )!
    }
}
