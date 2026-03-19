//
//  BackendAPIClient.swift
//  Empy_Swift
//
//  Created by AI Agent on 2026-03-19.
//  Backend API integration for real-time coaching
//

import Foundation

/// Client for empy-py-backend API
class BackendAPIClient {
    static let shared = BackendAPIClient()
    
    private let baseURL: String
    private let session: URLSession
    
    init(baseURL: String? = nil) {
        // TODO: Load from config/environment
        // For now, use placeholder or override in tests
        self.baseURL = baseURL ?? "https://api.empy.com"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Get Advice
    
    /// Get coaching advice from agent based on nudge
    /// - Parameter nudge: User query or detected event
    /// - Returns: Agent response with text and optional quick reply buttons
    func getAdvice(nudge: Nudge) async throws -> AdviceResponse {
        let url = URL(string: "\(baseURL)/advice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add authentication header if needed
        // request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody = AdviceRequest(nudge: nudge)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        do {
            return try JSONDecoder().decode(AdviceResponse.self, from: data)
        } catch {
            print("Failed to decode AdviceResponse: \(error)")
            throw APIError.invalidResponse
        }
    }
    
    // MARK: - Process Transcript
    
    /// Process transcript messages to detect nudges (questions, tension, etc.)
    /// - Parameters:
    ///   - conversationId: Unique conversation identifier
    ///   - messages: New transcript messages to analyze
    /// - Returns: Array of detected nudges
    func processTranscript(
        conversationId: String,
        messages: [TranscriptMessage]
    ) async throws -> [DetectedNudge] {
        let url = URL(string: "\(baseURL)/process")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add authentication header if needed
        
        let requestBody = ProcessRequest(
            conversationId: conversationId,
            transcript: messages.map { TranscriptLine(from: $0) }
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let processResponse = try JSONDecoder().decode(ProcessResponse.self, from: data)
            return processResponse.nudges
        } catch {
            print("Failed to decode ProcessResponse: \(error)")
            throw APIError.invalidResponse
        }
    }
}

// MARK: - Models

/// Request wrapper for /advice endpoint
struct AdviceRequest: Codable {
    let nudge: Nudge
}

/// Nudge data (user query or detected event)
struct Nudge: Codable {
    let type: String
    let text: String
    let conversationId: String?
    var previousMessageId: String?
    
    init(
        type: String,
        text: String,
        conversationId: String? = nil,
        previousMessageId: String? = nil
    ) {
        self.type = type
        self.text = text
        self.conversationId = conversationId
        self.previousMessageId = previousMessageId
    }
}

/// Response from /advice endpoint
struct AdviceResponse: Codable {
    let text: String
    let buttons: [String]?
}

/// Request for /process endpoint
struct ProcessRequest: Codable {
    let conversationId: String
    let transcript: [TranscriptLine]
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case transcript
    }
}

/// Transcript line for backend processing
struct TranscriptLine: Codable {
    let speaker: String
    let text: String
    let timestamp: Double
    
    init(speaker: String, text: String, timestamp: Double) {
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
    
    init(from message: TranscriptMessage) {
        self.speaker = message.speaker
        self.text = message.text
        self.timestamp = message.timestamp.timeIntervalSince1970
    }
}

/// Response from /process endpoint
struct ProcessResponse: Codable {
    let nudges: [DetectedNudge]
}

/// Detected nudge from transcript analysis
struct DetectedNudge: Codable, Identifiable {
    let id: String
    let type: String
    let text: String
    let timestamp: Double?
}

/// API error types
enum APIError: Error, LocalizedError {
    case serverError(statusCode: Int)
    case invalidResponse
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized - check API credentials"
        }
    }
}

// MARK: - TranscriptMessage Protocol

/// Protocol for transcript messages (to be implemented by existing TranscriptMessage type)
/// If your existing type doesn't match, create an extension or adapter
protocol TranscriptMessage {
    var speaker: String { get }
    var text: String { get }
    var timestamp: Date { get }
}

// Example extension if needed:
// extension YourExistingTranscriptMessage: TranscriptMessage {
//     var speaker: String { return self.speakerName }
//     var text: String { return self.utterance }
//     var timestamp: Date { return self.time }
// }
