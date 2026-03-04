//
//  TranscriptSegment.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Data models for transcript segments and state
//

import Foundation

/// A segment of transcribed speech
struct TranscriptSegment: Identifiable, Equatable {
    let id: UUID
    let text: String
    let speaker: String? // Optional speaker label
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let isFinal: Bool
    let timestamp: Date // When received
    
    init(
        text: String,
        speaker: String? = nil,
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 0,
        confidence: Double,
        isFinal: Bool
    ) {
        self.id = UUID()
        self.text = text
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isFinal = isFinal
        self.timestamp = Date()
    }
    
    // Equatable conformance
    static func == (lhs: TranscriptSegment, rhs: TranscriptSegment) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Full transcript state
struct TranscriptState {
    var segments: [TranscriptSegment] = []
    
    /// Joined full text from all segments
    var fullText: String {
        segments.map { $0.text }.joined(separator: " ")
    }
    
    /// Total word count across all segments
    var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
    }
    
    /// Count of final segments
    var finalCount: Int {
        segments.filter { $0.isFinal }.count
    }
    
    /// Count of partial segments (should be 0 or 1)
    var partialCount: Int {
        segments.filter { !$0.isFinal }.count
    }
}
