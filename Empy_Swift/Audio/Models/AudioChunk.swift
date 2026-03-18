import Foundation

/// Audio source type for dual-stream capture
enum AudioSource {
    case microphone
    case system
}

/// Represents a chunk of audio data captured from microphone or system
struct AudioChunk {
    /// Audio source (microphone or system)
    let source: AudioSource
    
    /// Monotonically increasing sequence ID, starting at 0
    let seqId: UInt64
    
    /// PCM audio data: 16kHz, 16-bit signed little-endian, mono
    let pcmData: Data
    
    /// Elapsed time in milliseconds since session start (from mach_absolute_time)
    let sessionElapsedMs: Int64
    
    /// Number of bytes in pcmData
    let byteCount: Int
}
