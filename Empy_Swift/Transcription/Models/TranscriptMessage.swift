//
//  TranscriptMessage.swift
//  Empy_Swift
//
//  T12 FIX: Missing model for transcript messages
//

import Foundation

/// Represents a single message in the conversation transcript
struct TranscriptMessage: Identifiable {
    let id: UUID
    let speaker: Speaker
    let text: String
    let timestamp: Date
    let isFinal: Bool
    
    init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        timestamp: Date = Date(),
        isFinal: Bool = true
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
    }
}

/// Speaker in a conversation
enum Speaker: Equatable {
    case you
    case participant(name: String)
}
