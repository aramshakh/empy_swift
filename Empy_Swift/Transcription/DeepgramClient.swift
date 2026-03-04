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
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript transcript: String)
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String)
    func deepgramClient(_ client: DeepgramClient, didEncounterError error: Error)
    func deepgramClientDidConnect(_ client: DeepgramClient)
    func deepgramClientDidDisconnect(_ client: DeepgramClient)
}

/// WebSocket client for Deepgram live transcription
class DeepgramClient: NSObject, URLSessionWebSocketDelegate {
    weak var delegate: DeepgramClientDelegate?
    
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
            URLQueryItem(name: "utterance_end_ms", value: "1000"),
            // Pass API key as query param — URLSessionWebSocketTask can strip
            // custom headers during the HTTP→WS upgrade handshake
            URLQueryItem(name: "token", value: AppConfig.deepgramApiKey)
        ]
        
        if FeatureFlags.multilingualEnabled {
            // Multi-language code-switching (e.g. English + Russian)
            // Deepgram recommends endpointing=100 for code-switching
            queryItems.append(URLQueryItem(name: "language", value: "multi"))
            queryItems.append(URLQueryItem(name: "model", value: "nova-2"))
            queryItems.append(URLQueryItem(name: "endpointing", value: "100"))
        } else {
            // Default: no language param, Deepgram auto-detects English
            // endpointing in ms — how long silence before Deepgram emits a final
            queryItems.append(URLQueryItem(name: "endpointing", value: "300"))
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
        
        // Emit partial or final transcript
        if result.isFinal == true || result.speechFinal == true {
            logger.log(
                event: "deepgram_final_transcript",
                layer: "transcription",
                details: [
                    "text": String(transcript.prefix(50)),
                    "confidence": String(format: "%.2f", alternative.confidence)
                ]
            )
            delegate?.deepgramClient(self, didReceiveFinalTranscript: transcript)
        } else {
            logger.log(event: "deepgram_partial_transcript", layer: "transcription")
            delegate?.deepgramClient(self, didReceivePartialTranscript: transcript)
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
