//
//  TranscriptEngine.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Manages transcript accumulation and state from Deepgram
//

import Foundation
import Combine

/// Manages transcript accumulation and state
class TranscriptEngine: ObservableObject {
    /// Current transcript state (observable for UI)
    @Published private(set) var transcriptState = TranscriptState()
    
    /// Deepgram client for receiving transcripts
    private let deepgramClient: DeepgramClient
    
    /// Session logger
    private let logger: SessionLogger
    
    /// Partial transcript cache (replaced by finals)
    private var partialSegments: [UUID: TranscriptSegment] = [:]
    
    /// Last partial segment ID (for replacement)
    private var lastPartialID: UUID?
    
    /// Last final transcript timestamp (for out-of-order protection)
    private var lastFinalTimestamp: Date?
    
    init(
        deepgramClient: DeepgramClient,
        logger: SessionLogger = .shared
    ) {
        self.deepgramClient = deepgramClient
        self.logger = logger
        self.deepgramClient.delegate = self
    }
    
    // MARK: - Public API
    
    /// Start transcription session
    func startSession() {
        clearState()
        
        do {
            try deepgramClient.connect()
            logger.log(event: "transcription_session_started", layer: "transcript")
        } catch {
            logger.log(
                event: "transcription_session_failed",
                layer: "transcript",
                details: ["error": error.localizedDescription]
            )
        }
    }
    
    /// End transcription session
    func endSession() {
        deepgramClient.disconnect()
        persistCurrentSession()
        logger.log(
            event: "transcription_session_ended",
            layer: "transcript",
            details: [
                "final_word_count": "\(transcriptState.wordCount)",
                "segment_count": "\(transcriptState.finalCount)"
            ]
        )
    }
    
    /// Clear all transcript state
    func clearState() {
        transcriptState = TranscriptState()
        partialSegments.removeAll()
        lastPartialID = nil
        lastFinalTimestamp = nil
        
        logger.log(event: "transcript_state_cleared", layer: "transcript")
    }
    
    /// Send audio chunk to Deepgram
    func processAudioChunk(_ audioData: Data) {
        deepgramClient.send(audioData: audioData)
    }
    
    private func persistCurrentSession() {
        let finalSegments = transcriptState.segments.filter { $0.isFinal }
        guard !finalSegments.isEmpty else { return }

        do {
            let fm = FileManager.default
            let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = appSupport
                .appendingPathComponent("com.empy.Empy_Swift", isDirectory: true)
                .appendingPathComponent("transcripts", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "session_\(formatter.string(from: Date())).json"
            let fileURL = dir.appendingPathComponent(filename)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(finalSegments)
            try data.write(to: fileURL)

            logger.log(
                event: "transcript_session_persisted",
                layer: "transcript",
                details: [
                    "path": fileURL.path,
                    "segments": "\(finalSegments.count)"
                ]
            )
        } catch {
            logger.log(
                event: "transcript_session_persist_failed",
                layer: "transcript",
                details: ["error": error.localizedDescription]
            )
        }
    }
}

// MARK: - DeepgramClientDelegate

extension TranscriptEngine: DeepgramClientDelegate {
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript transcript: String, speaker: String?) {
        // All state mutations on main thread — avoids data race between
        // background URLSession callbacks and async main-thread blocks
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = Date()
            
            // Ignore partials that arrive shortly after a final (out-of-order protection)
            if let lastFinal = self.lastFinalTimestamp, now.timeIntervalSince(lastFinal) < 1.0 {
                return
            }
            
            // Remove previous partial
            if let oldID = self.lastPartialID {
                self.partialSegments.removeValue(forKey: oldID)
                self.transcriptState.segments.removeAll { $0.id == oldID }
            }
            
            let segment = TranscriptSegment(
                text: transcript,
                speaker: speaker,
                confidence: 0.0,
                isFinal: false
            )
            self.partialSegments[segment.id] = segment
            self.lastPartialID = segment.id
            self.transcriptState.segments.append(segment)
        }
        
        let wordCount = transcript.split(whereSeparator: { $0.isWhitespace }).count
        logger.log(
            event: "transcript_partial_received",
            layer: "transcript",
            details: ["length": "\(transcript.count)", "words": "\(wordCount)"]
        )
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String, speaker: String?) {
        guard !transcript.isEmpty else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            // Remove any pending partial (replaced by this final)
            if let oldID = self.lastPartialID {
                self.partialSegments.removeValue(forKey: oldID)
                self.transcriptState.segments.removeAll { $0.id == oldID }
                self.lastPartialID = nil
            }
            
            let segment = TranscriptSegment(
                text: transcript,
                speaker: speaker,
                confidence: 1.0,
                isFinal: true
            )
            self.transcriptState.segments.append(segment)
            self.lastFinalTimestamp = Date()
        }
        
        let wordCount = transcript.split(whereSeparator: { $0.isWhitespace }).count
        logger.log(
            event: "transcript_final_received",
            layer: "transcript",
            details: [
                "text": String(transcript.prefix(50)),
                "word_count": "\(wordCount)"
            ]
        )
    }
    
    func deepgramClient(_ client: DeepgramClient, didEncounterError error: Error) {
        logger.log(
            event: "transcript_error",
            layer: "transcript",
            details: ["error": error.localizedDescription]
        )
    }
    
    func deepgramClientDidConnect(_ client: DeepgramClient) {
        logger.log(event: "transcript_connected", layer: "transcript")
    }
    
    func deepgramClientDidDisconnect(_ client: DeepgramClient) {
        logger.log(event: "transcript_disconnected", layer: "transcript")
    }
}
