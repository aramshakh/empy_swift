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
    func startSession() throws {
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
            throw error
        }
    }
    
    /// End transcription session
    func endSession() {
        // Convert any pending partial to final before disconnecting
        if let lastID = lastPartialID,
           let partialSegment = partialSegments[lastID] {
            // Remove partial
            transcriptState.segments.removeAll { $0.id == lastID }
            partialSegments.removeValue(forKey: lastID)
            
            // Add as final
            let finalSegment = TranscriptSegment(
                text: partialSegment.text,
                speaker: partialSegment.speaker,
                startTime: partialSegment.startTime,
                endTime: partialSegment.endTime,
                confidence: partialSegment.confidence,
                isFinal: true
            )
            transcriptState.segments.append(finalSegment)
            lastPartialID = nil
            
            logger.log(
                event: "transcript_partial_finalized_on_stop",
                layer: "transcript",
                details: ["text": String(partialSegment.text.prefix(50))]
            )
        }
        
        deepgramClient.disconnect()
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
}

// MARK: - DeepgramClientDelegate

extension TranscriptEngine: DeepgramClientDelegate {
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript transcript: String) {
        let now = Date()
        
        // Ignore partials that arrive shortly after a final (out-of-order protection)
        if let lastFinal = lastFinalTimestamp, now.timeIntervalSince(lastFinal) < 1.0 {
            logger.log(
                event: "transcript_partial_ignored",
                layer: "transcript",
                details: ["reason": "recent_final"]
            )
            return
        }
        
        // Remove previous partial
        if let lastID = lastPartialID {
            partialSegments.removeValue(forKey: lastID)
            transcriptState.segments.removeAll { $0.id == lastID }
        }
        
        // Add new partial
        let segment = TranscriptSegment(
            text: transcript,
            confidence: 0.0, // Partials have unknown confidence
            isFinal: false
        )
        
        partialSegments[segment.id] = segment
        lastPartialID = segment.id
        transcriptState.segments.append(segment)
        
        let wordCount = transcript.split(whereSeparator: { $0.isWhitespace }).count
        logger.log(
            event: "transcript_partial_received",
            layer: "transcript",
            details: [
                "length": "\(transcript.count)",
                "words": "\(wordCount)"
            ]
        )
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String) {
        guard !transcript.isEmpty else { return }
        
        // Remove any partial segments (replaced by final)
        if let lastID = lastPartialID {
            partialSegments.removeValue(forKey: lastID)
            transcriptState.segments.removeAll { $0.id == lastID }
            lastPartialID = nil
        }
        
        // Add final segment
        let segment = TranscriptSegment(
            text: transcript,
            confidence: 1.0, // Finals are high confidence
            isFinal: true
        )
        
        transcriptState.segments.append(segment)
        lastFinalTimestamp = Date()
        
        let wordCount = transcript.split(whereSeparator: { $0.isWhitespace }).count
        logger.log(
            event: "transcript_final_received",
            layer: "transcript",
            details: [
                "text": String(transcript.prefix(50)),
                "word_count": "\(wordCount)",
                "total_words": "\(transcriptState.wordCount)"
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
