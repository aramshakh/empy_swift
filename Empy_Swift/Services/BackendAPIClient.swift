//
//  BackendAPIClient.swift
//  Empy_Swift
//
//  Created by AI Agent on 2026-03-19.
//  Integration with empy-py-backend API
//

import Foundation

/// Client for empy-py-backend API (https://github.com/empyai/empy-py-backend)
class BackendAPIClient {
    static let shared = BackendAPIClient()
    
    private let baseURL: String
    private let session: URLSession
    
    init(baseURL: String? = nil) {
        // TODO: Load from config/environment
        self.baseURL = baseURL ?? ProcessInfo.processInfo.environment["EMPY_BACKEND_URL"] ?? "http://localhost:8081"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - POST /advice
    
    /// Get coaching advice from agent based on nudge
    /// Endpoint: POST /advice
    /// - Parameter request: AdviceRequest with nudge data
    /// - Returns: AdviceResponse with coaching text
    func getAdvice(request: AdviceRequest) async throws -> AdviceResponse {
        let url = URL(string: "\(baseURL)/advice")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add Bearer token if authentication required
        // urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw APIError.conversationNotFound
            }
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(AdviceResponse.self, from: data)
    }
    
    // MARK: - POST /question-detector
    
    /// Detect if text contains a question
    /// Endpoint: POST /question-detector
    /// - Parameter text: Text to analyze
    /// - Returns: Detected question text or nil
    func detectQuestion(text: String) async throws -> String? {
        let url = URL(string: "\(baseURL)/question-detector")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let request = QuestionDetectorRequest(text: text)
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(QuestionDetectorResponse.self, from: data)
        return result.text
    }
}

// MARK: - Models (matching empy-py-backend)

/// Request for /advice endpoint
struct AdviceRequest: Codable {
    let nudge: Nudge
}

/// Nudge data (from backend models.py)
struct Nudge: Codable {
    let conversationId: String
    let nudgeId: String
    let text: String
    let timestamp: Int
    let type: String
    let severity: String
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case nudgeId = "nudge_id"
        case text
        case timestamp
        case type
        case severity
    }
    
    init(
        conversationId: String,
        nudgeId: String = UUID().uuidString,
        text: String,
        timestamp: Int = Int(Date().timeIntervalSince1970),
        type: String = "user_query",
        severity: String = ""
    ) {
        self.conversationId = conversationId
        self.nudgeId = nudgeId
        self.text = text
        self.timestamp = timestamp
        self.type = type
        self.severity = severity
    }
}

/// Response from /advice endpoint
struct AdviceResponse: Codable {
    let text: String
}

/// Request for /question-detector endpoint
struct QuestionDetectorRequest: Codable {
    let text: String
}

/// Response from /question-detector endpoint
struct QuestionDetectorResponse: Codable {
    let text: String?
}

/// API error types
enum APIError: Error, LocalizedError {
    case serverError(statusCode: Int)
    case invalidResponse
    case unauthorized
    case conversationNotFound
    
    var errorDescription: String? {
        switch self {
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized - authentication required"
        case .conversationNotFound:
            return "Conversation not found (404)"
        }
    }
}
