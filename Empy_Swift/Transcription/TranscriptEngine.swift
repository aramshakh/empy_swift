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
    
    // MARK: - 20-second bubble accumulation
    
    /// How long (seconds) to accumulate finals into one bubble before sealing
    private let bubbleDuration: TimeInterval = 20.0
    
    /// The currently open (accumulating) bubble segment — kept for stable-ID in-place updates
    private var activeBubble: TranscriptSegment?
    
    /// Text accumulated in the current bubble (finals only, no partial)
    private var activeBubbleText: String = ""
    
    /// When the current bubble was first opened
    private var bubbleStartTime: Date?
    
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
    func endSession() async {
        // Give Deepgram time to send final transcripts before disconnecting
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        await MainActor.run {
            // Flush any live partial into the active bubble as a final
            if let lastID = lastPartialID,
               let partialSegment = partialSegments[lastID] {
                transcriptState.segments.removeAll { $0.id == lastID }
                partialSegments.removeValue(forKey: lastID)
                lastPartialID = nil
                
                // Merge partial text into bubble
                let merged = activeBubbleText.isEmpty
                    ? partialSegment.text
                    : activeBubbleText + " " + partialSegment.text
                activeBubbleText = merged
                
                let sealed: TranscriptSegment
                if let existing = activeBubble {
                    sealed = TranscriptSegment(updating: existing, text: activeBubbleText, confidence: 1.0, isFinal: true)
                    if let idx = transcriptState.segments.firstIndex(where: { $0.id == existing.id }) {
                        transcriptState.segments[idx] = sealed
                    } else {
                        transcriptState.segments.append(sealed)
                    }
                } else {
                    sealed = TranscriptSegment(text: activeBubbleText, confidence: 1.0, isFinal: true)
                    transcriptState.segments.append(sealed)
                }
                activeBubble = nil
                activeBubbleText = ""
                bubbleStartTime = nil
                
                logger.log(event: "transcript_partial_finalized_on_stop", layer: "transcript")
            }
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
        activeBubble = nil
        activeBubbleText = ""
        bubbleStartTime = nil
        
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            // Remove previous partial segment from the array
            if let oldID = self.lastPartialID {
                self.partialSegments.removeValue(forKey: oldID)
                self.transcriptState.segments.removeAll { $0.id == oldID }
            }
            
            // Show partial as: accumulatedFinalText + " " + currentPartialText
            // This gives the user a live preview inside the current bubble
            let previewText = self.activeBubbleText.isEmpty
                ? transcript
                : self.activeBubbleText + " " + transcript
            
            let segment = TranscriptSegment(
                text: previewText,
                confidence: 0.0,
                isFinal: false
            )
            self.partialSegments[segment.id] = segment
            self.lastPartialID = segment.id
            self.transcriptState.segments.append(segment)
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String) {
        guard !transcript.isEmpty else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            // Remove the live partial preview
            if let oldID = self.lastPartialID {
                self.partialSegments.removeValue(forKey: oldID)
                self.transcriptState.segments.removeAll { $0.id == oldID }
                self.lastPartialID = nil
            }
            
            let now = Date()
            
            // Decide: add to current bubble, or seal it and open a new one
            let shouldSeal: Bool
            if let start = self.bubbleStartTime {
                shouldSeal = now.timeIntervalSince(start) >= self.bubbleDuration
            } else {
                shouldSeal = false // no bubble open yet
            }
            
            if shouldSeal {
                // Seal current bubble — it stays in transcriptState as a closed final segment
                self.activeBubble = nil
                self.activeBubbleText = ""
                self.bubbleStartTime = nil
            }
            
            // Append this final to the active bubble text
            if self.activeBubbleText.isEmpty {
                self.activeBubbleText = transcript
            } else {
                self.activeBubbleText += " " + transcript
            }
            
            if let existing = self.activeBubble {
                // Update existing bubble in-place using same stable ID — no ForEach flicker
                let updated = TranscriptSegment(updating: existing, text: self.activeBubbleText, confidence: 1.0, isFinal: true)
                if let idx = self.transcriptState.segments.firstIndex(where: { $0.id == existing.id }) {
                    self.transcriptState.segments[idx] = updated
                } else {
                    self.transcriptState.segments.append(updated)
                }
                self.activeBubble = updated
            } else {
                // Open a new bubble
                let newBubble = TranscriptSegment(text: self.activeBubbleText, confidence: 1.0, isFinal: true)
                self.activeBubble = newBubble
                self.bubbleStartTime = now
                self.transcriptState.segments.append(newBubble)
            }
            
            self.lastFinalTimestamp = now
            
            self.logger.log(
                event: "transcript_final_received",
                layer: "transcript",
                details: [
                    "text": String(transcript.prefix(50)),
                    "bubble_age": self.bubbleStartTime.map { String(format: "%.1fs", now.timeIntervalSince($0)) } ?? "new"
                ]
            )
        }
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
