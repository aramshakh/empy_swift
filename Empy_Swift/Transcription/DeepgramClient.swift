//
//  DeepgramClient.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  WebSocket client for Deepgram streaming transcription API
//

import Foundation

extension Notification.Name {
    static let transcriptionDegraded = Notification.Name("transcriptionDegraded")
}

/// Delegate protocol for Deepgram transcription events
protocol DeepgramClientDelegate: AnyObject {
    /// Deepgram interim result — text still being refined.
    /// `speaker` is non-nil only when the client has a `speakerResolver` configured.
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript transcript: String, speaker: String?)
    /// Deepgram isFinal=true — text confirmed for this utterance chunk
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String, speaker: String?)
    /// Deepgram speechFinal=true — speaker paused, utterance complete → seal bubble
    func deepgramClient(_ client: DeepgramClient, didReceiveSpeechFinal transcript: String, speaker: String?)
    /// Deepgram UtteranceEnd event — 1200ms silence detected → seal bubble
    func deepgramClientDidReceiveUtteranceEnd(_ client: DeepgramClient)
    func deepgramClient(_ client: DeepgramClient, didEncounterError error: Error)
    func deepgramClientDidConnect(_ client: DeepgramClient)
    func deepgramClientDidDisconnect(_ client: DeepgramClient)
}

/// WebSocket client for Deepgram live transcription
class DeepgramClient: NSObject, URLSessionWebSocketDelegate {
    weak var delegate: DeepgramClientDelegate?

    /// Optional closure that maps a Deepgram speaker ID (0, 1, 2…) to a display label.
    /// When nil, the client fires delegate methods without a speaker label embedded in text.
    /// Used by the system audio stream to route diarized speakers to separate bubbles.
    var speakerResolver: ((Int?) -> String)?

    /// Whether to request diarization from Deepgram.
    /// Enable only on the system audio stream (multiple real speakers).
    /// The mic stream is always a single speaker ("you") — diarize wastes compute and
    /// can misattribute silence-padded audio to a phantom second speaker.
    var useDiarization: Bool = false

    // Dependencies
    private let logger: SessionLogger
    
    // WebSocket state
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private(set) var isConnected = false
    private var connectionStartTime: Date?
    
    // Reconnection management
    private var reconnectionStrategy = ReconnectionStrategy()
    private var reconnectWorkItem: DispatchWorkItem?
    private var manualDisconnect = false
    
    // Audio buffering during disconnect
    private var audioBuffer: [Data] = []
    private let maxBufferDuration: TimeInterval = 30.0
    private var bufferStartTime: Date?
    private let maxBufferSize = 960_000 // ~30 seconds at 16kHz mono Int16
    
    // Degradation tracking
    private var degradationTimer: Timer?
    private let degradationThreshold: TimeInterval = 60.0
    
    init(logger: SessionLogger = .shared) {
        self.logger = logger
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.log(event: "deepgram_ws_handshake_ok", layer: "transcription")
        // Handshake succeeded — actual isConnected is set on first transcript
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        logger.log(
            event: "deepgram_ws_closed",
            layer: "transcription",
            details: ["code": "\(closeCode.rawValue)", "reason": reasonStr]
        )
        handleDisconnection()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logger.log(
                event: "deepgram_ws_task_error",
                layer: "transcription",
                details: ["error": error.localizedDescription]
            )
            handleDisconnection()
        }
    }
    
    // MARK: - Public API
    
    /// Connect to Deepgram WebSocket
    func connect() throws {
        guard AppConfig.hasValidDeepgramKey else {
            throw DeepgramClientError.missingAPIKey
        }
        
        // Build WebSocket URL (includes token query param for auth)
        let url = buildWebSocketURL()
        var request = URLRequest(url: url)
        request.setValue("Token \(AppConfig.deepgramApiKey)", forHTTPHeaderField: "Authorization")
        
        // Create WebSocket task
        webSocketTask = session.webSocketTask(with: request)
        
        manualDisconnect = false
        webSocketTask?.resume()
        startReceiving()

        isConnected = false
        connectionStartTime = nil
        
        logger.log(event: "deepgram_connecting", layer: "transcription")
        
        // Start degradation timer
        startDegradationTimer()
    }
    
    /// Disconnect from Deepgram WebSocket
    func disconnect() {
        manualDisconnect = true
        stopDegradationTimer()
        stopReconnectTimer()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        audioBuffer.removeAll()
        bufferStartTime = nil
        
        logger.log(event: "deepgram_disconnected", layer: "transcription")
    }
    
    /// Send audio data to Deepgram
    func send(audioData: Data) {
        guard let task = webSocketTask else {
            // Buffer audio if disconnected
            bufferAudio(audioData)
            return
        }
        
        // Send as binary frame
        let message = URLSessionWebSocketTask.Message.data(audioData)
        task.send(message) { [weak self] error in
            guard let self = self else { return }
            guard task === self.webSocketTask else { return }
            if let error = error {
                self.logger.log(
                    event: "deepgram_send_failed",
                    layer: "transcription",
                    details: ["error": error.localizedDescription]
                )
                self.handleDisconnection()
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func buildWebSocketURL() -> URL {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        var queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "utterance_end_ms", value: "1200"),
            URLQueryItem(name: "vad_events", value: "true"),
            // Pass API key as query param — URLSessionWebSocketTask can strip
            // custom headers during the HTTP→WS upgrade handshake
            URLQueryItem(name: "token", value: AppConfig.deepgramApiKey)
        ]
        
        if FeatureFlags.multilingualEnabled {
            // Multi-language code-switching (e.g. English + Russian)
            // Deepgram recommends endpointing=100 for code-switching
            queryItems.append(URLQueryItem(name: "language", value: "multi"))
            queryItems.append(URLQueryItem(name: "model", value: "nova-3"))
            queryItems.append(URLQueryItem(name: "endpointing", value: "100"))
        } else {
            // Default: no language param, Deepgram auto-detects
            queryItems.append(URLQueryItem(name: "endpointing", value: "300"))
        }

        // Diarization only for streams with multiple real speakers (system audio).
        // Disabled on the mic stream — always one speaker, and diarize adds latency.
        // max_speakers=2 tells Deepgram to expect exactly 2 speakers — reduces phantom
        // third-speaker errors that occur when the model over-segments on silence/tone changes.
        if useDiarization {
            queryItems.append(URLQueryItem(name: "diarize", value: "true"))
            queryItems.append(URLQueryItem(name: "diarize_version", value: "latest"))
        }

        components.queryItems = queryItems
        return components.url!
    }
    
    private func startReceiving(task: URLSessionWebSocketTask? = nil) {
        let activeTask = task ?? webSocketTask
        guard let activeTask = activeTask else { return }

        activeTask.receive { [weak self] result in
            guard let self = self else { return }
            guard activeTask === self.webSocketTask else { return }

            switch result {
            case .success(let message):
                self.handleReceivedMessage(message)
                self.startReceiving(task: activeTask)

            case .failure(let error):
                self.logger.log(
                    event: "deepgram_receive_error",
                    layer: "transcription",
                    details: ["error": error.localizedDescription]
                )
                self.handleDisconnection()
            }
        }
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleJSONMessage(text)
            
        case .data(_):
            // Binary messages not expected from Deepgram
            logger.log(event: "deepgram_unexpected_binary", layer: "transcription")
            
        @unknown default:
            break
        }
    }
    
    private func handleJSONMessage(_ jsonString: String) {
        let response = DeepgramResponse(from: jsonString)
        
        switch response {
        case .transcript(let result):
            handleTranscriptResult(result)
            
        case .utteranceEnd:
            print("🔔 UTTERANCE_END received → sealing bubble")
            logger.log(event: "deepgram_utterance_end", layer: "transcription")
            delegate?.deepgramClientDidReceiveUtteranceEnd(self)
            
        case .metadata(let metadata):
            handleMetadata(metadata)
            
        case .error(let error):
            handleError(error)
            
        case .unknown(let raw):
            logger.log(
                event: "deepgram_unknown_message",
                layer: "transcription",
                details: ["message": String(raw.prefix(100))]
            )
        }
    }
    
    private func handleTranscriptResult(_ result: DeepgramTranscriptResult) {
        guard let channel = result.channel,
              let alternative = channel.alternatives.first else {
            return
        }

        let transcript = alternative.transcript
        guard !transcript.isEmpty else { return }

        // First successful transcript confirms stream is healthy
        if !isConnected {
            isConnected = true
            connectionStartTime = Date()
            reconnectionStrategy.reset()
            stopDegradationTimer()
            flushAudioBuffer()
            delegate?.deepgramClientDidConnect(self)
        }

        // Route to the right delegate method based on Deepgram flags:
        //   speechFinal=true  → speaker paused (utterance complete) → seal bubble
        //   isFinal=true only → chunk confirmed but speaker may still be talking
        //   neither           → interim/partial (still being refined)
        if result.speechFinal == true {
            logger.log(
                event: "deepgram_speech_final",
                layer: "transcription",
                details: ["text": String(transcript.prefix(50))]
            )
            // For speechFinal, split by speaker and emit each group separately
            let chunks = speakerChunks(from: alternative)
            for chunk in chunks {
                delegate?.deepgramClient(self, didReceiveSpeechFinal: chunk.text, speaker: chunk.speaker)
            }

        } else if result.isFinal == true {
            logger.log(
                event: "deepgram_final_transcript",
                layer: "transcription",
                details: [
                    "text": String(transcript.prefix(50)),
                    "confidence": String(format: "%.2f", alternative.confidence)
                ]
            )
            // Split isFinal chunk by speaker groups — each group → own bubble
            let chunks = speakerChunks(from: alternative)
            for chunk in chunks {
                delegate?.deepgramClient(self, didReceiveFinalTranscript: chunk.text, speaker: chunk.speaker)
            }

        } else {
            // Partial: don't split by speaker — diarization is unstable on partials.
            // Use first word's speaker as a hint; the bubble will be corrected on isFinal.
            let rawSpeakerId = alternative.words?.first?.speaker
            let resolvedSpeaker = speakerResolver?(rawSpeakerId)
            logger.log(event: "deepgram_partial_transcript", layer: "transcription")
            delegate?.deepgramClient(self, didReceivePartialTranscript: transcript, speaker: resolvedSpeaker)
        }
    }

    /// Groups words by consecutive speaker, returns (speaker label, joined text) pairs.
    /// Falls back to a single chunk with the full transcript when no word-level diarization.
    private func speakerChunks(from alternative: DeepgramTranscriptResult.Alternative) -> [(text: String, speaker: String?)] {
        guard let resolver = speakerResolver,
              let words = alternative.words, !words.isEmpty else {
            // No diarization configured or no words — single chunk
            let fallbackSpeaker = speakerResolver?(alternative.words?.first?.speaker)
            return [(text: alternative.transcript, speaker: fallbackSpeaker)]
        }

        // Group consecutive words with the same speaker ID
        var groups: [(speakerId: Int?, words: [String])] = []
        for word in words {
            if let last = groups.last, last.speakerId == word.speaker {
                groups[groups.count - 1].words.append(word.word)
            } else {
                groups.append((speakerId: word.speaker, words: [word.word]))
            }
        }

        return groups.map { group in
            (text: group.words.joined(separator: " "), speaker: resolver(group.speakerId))
        }
    }
    
    private func handleMetadata(_ metadata: DeepgramMetadata) {
        logger.log(
            event: "deepgram_metadata",
            layer: "transcription",
            details: [
                "type": metadata.type,
                "request_id": metadata.requestId ?? "none"
            ]
        )
    }
    
    private func handleError(_ error: DeepgramError) {
        logger.log(
            event: "deepgram_api_error",
            layer: "transcription",
            details: [
                "message": error.message,
                "description": error.description ?? "none"
            ]
        )
        
        let nsError = NSError(
            domain: "DeepgramClient",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: error.message]
        )
        delegate?.deepgramClient(self, didEncounterError: nsError)
    }
    
    private func handleDisconnection() {
        guard !manualDisconnect else { return }
        
        isConnected = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        delegate?.deepgramClientDidDisconnect(self)
        
        logger.log(event: "deepgram_disconnected_unexpected", layer: "transcription")
        
        // Start buffering
        if bufferStartTime == nil {
            bufferStartTime = Date()
        }
        
        // Attempt reconnect
        attemptReconnect()
    }
    
    private func attemptReconnect() {
        guard let delay = reconnectionStrategy.nextDelay() else {
            logger.log(event: "deepgram_reconnect_exhausted", layer: "transcription")
            emitDegradation()
            return
        }

        logger.log(
            event: "deepgram_reconnect_scheduled",
            layer: "transcription",
            details: ["delay": String(format: "%.1fs", delay), "attempt": "\(reconnectionStrategy.attempt)"]
        )

        stopReconnectTimer()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            do {
                try self.connect()
            } catch {
                self.logger.log(
                    event: "deepgram_reconnect_failed",
                    layer: "transcription",
                    details: ["error": error.localizedDescription]
                )
                self.attemptReconnect()
            }
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func stopReconnectTimer() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }
    
    // MARK: - Audio Buffering
    
    private func bufferAudio(_ data: Data) {
        // Calculate current buffer size
        let currentSize = audioBuffer.reduce(0) { $0 + $1.count }
        
        // Check if buffer full
        guard currentSize + data.count <= maxBufferSize else {
            // Drop oldest chunk
            if !audioBuffer.isEmpty {
                audioBuffer.removeFirst()
            }
            audioBuffer.append(data)
            return
        }
        
        audioBuffer.append(data)
        
        logger.log(
            event: "deepgram_audio_buffered",
            layer: "transcription",
            details: ["buffer_count": "\(audioBuffer.count)"]
        )
    }
    
    private func flushAudioBuffer() {
        guard !audioBuffer.isEmpty else { return }
        
        logger.log(
            event: "deepgram_buffer_flush_start",
            layer: "transcription",
            details: ["chunks": "\(audioBuffer.count)"]
        )
        
        for chunk in audioBuffer {
            send(audioData: chunk)
        }
        
        audioBuffer.removeAll()
        bufferStartTime = nil
        
        logger.log(event: "deepgram_buffer_flush_complete", layer: "transcription")
    }
    
    // MARK: - Degradation Tracking
    
    private func startDegradationTimer() {
        stopDegradationTimer()
        degradationTimer = Timer.scheduledTimer(
            withTimeInterval: degradationThreshold,
            repeats: false
        ) { [weak self] _ in
            self?.emitDegradation()
        }
    }
    
    private func stopDegradationTimer() {
        degradationTimer?.invalidate()
        degradationTimer = nil
    }
    
    private func emitDegradation() {
        logger.log(event: "deepgram_degraded", layer: "transcription")
        
        // Clear buffer (stop buffering new audio)
        audioBuffer.removeAll()
        bufferStartTime = nil
        
        // Notify SessionManager
        NotificationCenter.default.post(name: .transcriptionDegraded, object: nil)
        
        let error = NSError(
            domain: "DeepgramClient",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Transcription unavailable for 60+ seconds"]
        )
        delegate?.deepgramClient(self, didEncounterError: error)
    }
}

// MARK: - Errors

enum DeepgramClientError: LocalizedError {
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Deepgram API key not configured"
        }
    }
}
