//
//  DeepgramMessage.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Data models for Deepgram WebSocket API messages
//

import Foundation

/// Deepgram transcript result (inbound message)
/// JSON uses snake_case: is_final, speech_final — mapped via CodingKeys
struct DeepgramTranscriptResult: Codable {
    let type: String?
    let channel: Channel?
    let isFinal: Bool?
    let speechFinal: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
    }
    
    struct Channel: Codable {
        let alternatives: [Alternative]
    }
    
    struct Alternative: Codable {
        let transcript: String
        let confidence: Double
        let words: [Word]?
    }
    
    struct Word: Codable {
        let word: String
        let start: Double
        let end: Double
        let confidence: Double
    }
}

/// Deepgram metadata message (inbound)
struct DeepgramMetadata: Codable {
    let type: String
    let requestId: String?
    let modelUUID: String?
    let duration: Double?
    
    enum CodingKeys: String, CodingKey {
        case type
        case requestId = "request_id"
        case modelUUID = "model_uuid"
        case duration
    }
}

/// Deepgram UtteranceEnd event — fired after utterance_end_ms of silence
/// Signals "speaker finished a sentence" → seal the current bubble
struct DeepgramUtteranceEnd: Codable {
    let type: String
    let channel: [Int]?
    let lastWordEnd: Double?
    
    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case lastWordEnd = "last_word_end"
    }
}

/// Deepgram error message (inbound)
struct DeepgramError: Codable {
    let type: String
    let message: String
    let description: String?
}

/// Union type for any Deepgram response
enum DeepgramResponse {
    case transcript(DeepgramTranscriptResult)
    case utteranceEnd(DeepgramUtteranceEnd)
    case metadata(DeepgramMetadata)
    case error(DeepgramError)
    case unknown(String)
    
    init(from jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else {
            self = .unknown("Invalid UTF-8")
            return
        }
        
        // Try to parse as transcript first (most common)
        if let transcript = try? JSONDecoder().decode(DeepgramTranscriptResult.self, from: data),
           transcript.type == "Results" {
            self = .transcript(transcript)
            return
        }
        
        // UtteranceEnd — "speaker finished a sentence"
        if let ue = try? JSONDecoder().decode(DeepgramUtteranceEnd.self, from: data),
           ue.type == "UtteranceEnd" {
            self = .utteranceEnd(ue)
            return
        }
        
        // Try metadata
        if let metadata = try? JSONDecoder().decode(DeepgramMetadata.self, from: data),
           metadata.type == "Metadata" {
            self = .metadata(metadata)
            return
        }
        
        // Try error
        if let error = try? JSONDecoder().decode(DeepgramError.self, from: data),
           error.type == "Error" {
            self = .error(error)
            return
        }
        
        // Unknown message type
        self = .unknown(jsonString)
    }
}
