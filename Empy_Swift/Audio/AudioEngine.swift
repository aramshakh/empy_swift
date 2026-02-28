import AVFoundation
import Combine

/// Audio engine for capturing microphone input and emitting PCM chunks
class AudioEngine: ObservableObject {
    /// Whether the engine is currently capturing audio
    @Published var isCapturing: Bool = false
    
    /// Callback invoked when an audio chunk is ready
    var onChunk: ((AudioChunk) -> Void)?
    
    /// AVAudioEngine instance
    private let engine = AVAudioEngine()
    
    /// Chunk emitter for buffering and emitting audio chunks
    private var chunkEmitter: ChunkEmitter?
    
    /// Audio format: 16kHz, mono, Int16 PCM
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )
    
    /// Start capturing audio from the microphone
    /// - Throws: Audio engine errors or permission errors
    func start() throws {
        // Request microphone permission
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)
        
        // Request permission if not already granted
        audioSession.requestRecordPermission { [weak self] granted in
            guard granted else {
                print("⚠️ Microphone permission denied")
                return
            }
            
            DispatchQueue.main.async {
                do {
                    try self?.setupEngine()
                } catch {
                    print("❌ Failed to setup engine: \(error)")
                }
            }
        }
    }
    
    /// Setup and start the audio engine
    private func setupEngine() throws {
        guard let targetFormat = targetFormat else {
            throw NSError(domain: "AudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"])
        }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create chunk emitter
        let emitter = ChunkEmitter()
        emitter.onChunk = { [weak self] chunk in
            self?.onChunk?(chunk)
        }
        self.chunkEmitter = emitter
        
        // Install tap on input node
        // We need to convert from the input format to our target format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let emitter = self.chunkEmitter else { return }
            
            // Convert audio buffer to target format
            guard let convertedBuffer = self.convert(buffer: buffer, to: targetFormat) else {
                return
            }
            
            // Extract PCM data from the buffer
            guard let pcmData = self.extractPCMData(from: convertedBuffer) else {
                return
            }
            
            // Append to chunk emitter
            emitter.append(samples: pcmData)
        }
        
        // Start the engine
        try engine.start()
        
        DispatchQueue.main.async {
            self.isCapturing = true
        }
        
        print("✅ Audio engine started")
    }
    
    /// Convert an audio buffer to the target format
    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return nil
        }
        
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("⚠️ Conversion error: \(error)")
            return nil
        }
        
        convertedBuffer.frameLength = convertedBuffer.frameCapacity
        return convertedBuffer
    }
    
    /// Extract PCM data from an audio buffer
    private func extractPCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // For mono audio, we only have one channel
        var data = Data(capacity: frameLength * MemoryLayout<Int16>.size)
        
        for channel in 0..<channelCount {
            let ptr = channelData[channel]
            let bufferPointer = UnsafeBufferPointer(start: ptr, count: frameLength)
            data.append(contentsOf: bufferPointer.map { $0 })
        }
        
        return data
    }
    
    /// Stop capturing audio
    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        chunkEmitter = nil
        
        DispatchQueue.main.async {
            self.isCapturing = false
        }
        
        print("🛑 Audio engine stopped")
    }
}
