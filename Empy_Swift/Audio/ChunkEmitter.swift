import Foundation
import Darwin

/// Buffers audio samples and emits chunks at regular intervals (~100ms)
class ChunkEmitter {
    /// Buffer for accumulating audio samples
    private var buffer: Data = Data()
    
    /// Current sequence ID
    private var seqId: UInt64 = 0
    
    /// Target chunk size in bytes (~100ms at 16kHz, 16-bit mono)
    /// 16000 Hz × 2 bytes × 0.1s = 3200 bytes
    private let chunkSize: Int = 3200
    
    /// Session start time in mach absolute time units
    private let startTime: UInt64
    
    /// Callback invoked when a chunk is ready
    var onChunk: ((AudioChunk) -> Void)?
    
    init() {
        self.startTime = mach_absolute_time()
    }
    
    /// Append audio samples to the buffer and emit chunks when ready
    /// - Parameter samples: Raw PCM data to append
    func append(samples: Data) {
        buffer.append(samples)
        
        // Emit chunks while we have enough data
        while buffer.count >= chunkSize {
            let chunkData = buffer.prefix(chunkSize)
            
            let chunk = AudioChunk(
                seqId: seqId,
                pcmData: Data(chunkData),
                sessionElapsedMs: calculateElapsed(),
                byteCount: chunkSize
            )
            
            onChunk?(chunk)
            
            buffer.removeFirst(chunkSize)
            seqId += 1
        }
    }
    
    /// Calculate elapsed time since session start in milliseconds
    /// Uses mach_absolute_time() for precise timing
    private func calculateElapsed() -> Int64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        
        let elapsed = mach_absolute_time() - startTime
        let nanoseconds = elapsed * UInt64(info.numer) / UInt64(info.denom)
        let milliseconds = Int64(nanoseconds / 1_000_000)
        
        return milliseconds
    }
}
