//
//  BackendAPIClient.swift
//  Empy_Swift
//
//  Created by AI Agent on 2026-03-19.
//  Integration with empy-py-backend API
//

import Foundation

/// Client for empy-py-backend API
class BackendAPIClient {
    static let shared = BackendAPIClient()

    private let baseURL: String
    private let session: URLSession

    init(baseURL: String? = nil) {
        self.baseURL = baseURL
            ?? ProcessInfo.processInfo.environment["EMPY_BACKEND_URL"]
            ?? AppConfig.backendEnvironment.baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Helpers

    private func makeRequest(path: String, method: String = "POST", auth: Bool = false) -> URLRequest {
        let url = URL(string: "\(baseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token = AppConfig.backendToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        // Log outgoing request
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
            print("📡 API \(method) \(url)\n   Body: \(bodyStr.prefix(500))")
        } else {
            print("📡 API \(method) \(url)")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        let responseStr = String(data: data, encoding: .utf8) ?? "<binary>"
        print("📡 API \(method) \(url) → \(http.statusCode)\n   Response: \(responseStr.prefix(500))")

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            if http.statusCode == 402 { throw APIError.subscriptionInactive }
            if http.statusCode == 404 { throw APIError.notFound }
            throw APIError.serverError(statusCode: http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - GET /health

    func health() async throws -> HealthResponse {
        var req = makeRequest(path: "/health", method: "GET")
        req.setValue(nil, forHTTPHeaderField: "Content-Type")
        return try await perform(req)
    }

    // MARK: - POST /conversation  (requires Bearer auth via userapi)

    func createConversation(request: ConversationInitRequest) async throws -> ConversationInitResponse {
        var req = makeRequest(path: "/conversation", auth: true)
        req.httpBody = try JSONEncoder().encode(request)
        return try await perform(req)
    }

    // MARK: - POST /conversation/{id}/end  (requires Bearer auth)

    func endConversation(id: String) async throws -> ConversationEndResponse {
        var req = makeRequest(path: "/conversation/\(id)/end", auth: true)
        req.httpBody = try JSONEncoder().encode(EmptyBody())
        return try await perform(req)
    }

    // MARK: - POST /process

    func process(request: ProcessRequest) async throws -> ProcessResponse {
        var req = makeRequest(path: "/process")
        req.httpBody = try JSONEncoder().encode(request)
        return try await perform(req)
    }

    // MARK: - POST /advice

    func getAdvice(request: AdviceRequest) async throws -> AdviceResponse {
        var req = makeRequest(path: "/advice")
        req.httpBody = try JSONEncoder().encode(request)
        return try await perform(req)
    }

    // MARK: - POST /question-detector

    func detectQuestion(text: String) async throws -> String? {
        var req = makeRequest(path: "/question-detector")
        req.httpBody = try JSONEncoder().encode(QuestionDetectorRequest(text: text))
        let result: QuestionDetectorResponse = try await perform(req)
        return result.text
    }
}

// MARK: - Models (matching models.py exactly)

// /health
struct HealthResponse: Codable {
    let status: String
    let version: String
}

// /conversation  →  ConversationInitRequest / ConversationInitResponse
struct MeetingInfo: Codable {
    let goal: String
    let duration: Int
    let participantContext: String?

    enum CodingKeys: String, CodingKey {
        case goal
        case duration
        case participantContext = "participant_context"
    }
}

struct ConversationInitRequest: Codable {
    let userId: String
    let meetingInfo: MeetingInfo?
    // agenda omitted — not used in iOS client

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case meetingInfo = "meeting_info"
    }

    init(userId: String, meetingInfo: MeetingInfo? = nil) {
        self.userId = userId
        self.meetingInfo = meetingInfo
    }
}

struct ConversationInitResponse: Codable {
    let conversationId: String  // UUID string from backend

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
    }
}

struct SummaryResponse: Codable {
    let takeaways: [String]
    let actionPoints: [String]

    enum CodingKeys: String, CodingKey {
        case takeaways
        case actionPoints = "action_points"
    }
}

struct ConversationEndResponse: Codable {
    let conversationId: String
    let summary: SummaryResponse
    let reportId: String?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case summary
        case reportId = "report_id"
    }
}

// /process  →  ProcessRequest / ProcessResponse
// Transcription matches models.py Transcription exactly
struct Transcription: Codable {
    let id: Int
    let text: String
    let timeStart: Int   // milliseconds from session start
    let timeEnd: Int
    let speaker: String  // "me" or "other"
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case timeStart = "time_start"
        case timeEnd   = "time_end"
        case speaker
        case type
    }

    init(id: Int, text: String, timeStart: Int, timeEnd: Int, speaker: String, type: String? = nil) {
        self.id = id
        self.text = text
        self.timeStart = timeStart
        self.timeEnd = timeEnd
        self.speaker = speaker
        self.type = type
    }
}

struct ProcessRequest: Codable {
    let id: String          // UUID string — conversation_id
    let conversation: [Transcription]
    let debug: Bool

    init(id: String, conversation: [Transcription], debug: Bool = false) {
        self.id = id
        self.conversation = conversation
        self.debug = debug
    }
}

struct ProcessResponse: Codable {
    let nudges: [Nudge]
    let feelings: [Feeling]
    let needs: [Need]
    let statistics: Statistics
}

struct Nudge: Codable {
    let conversationId: String
    let nudgeId: String
    let text: String
    let timestamp: Int
    let type: String
    let severity: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case nudgeId        = "nudge_id"
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

struct Feeling: Codable {
    let speaker: String
    let feeling: String
    let feelingCategory: String
    let timestamp: Int

    enum CodingKeys: String, CodingKey {
        case speaker
        case feeling
        case feelingCategory = "feeling_category"
        case timestamp
    }
}

struct Need: Codable {
    let speaker: String
    let need: String
    let strategy: String
    let description: String
    let recommendations: [String]
    let timestamp: Int
}

struct Statistics: Codable {
    let speakingRatio: SpeakingRatio
    let evaluationVsFactual: EvalVsFact

    enum CodingKeys: String, CodingKey {
        case speakingRatio       = "speaking_ratio"
        case evaluationVsFactual = "evaluation_vs_factual"
    }
}

struct SpeakingRatio: Codable {
    let speakers: [String: Double]
}

struct EvalVsFact: Codable {
    let factualStatements: [String: Int]
    let evaluativeStatements: [String: Int]

    enum CodingKeys: String, CodingKey {
        case factualStatements    = "factual_statements"
        case evaluativeStatements = "evaluative_statements"
    }
}

// /advice
struct AdviceRequest: Codable {
    let nudge: Nudge
}

struct AdviceResponse: Codable {
    let text: String
}

// /question-detector
struct QuestionDetectorRequest: Codable {
    let text: String
}

struct QuestionDetectorResponse: Codable {
    let text: String?
}

// Placeholder for empty POST bodies
private struct EmptyBody: Codable {}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case serverError(statusCode: Int)
    case invalidResponse
    case unauthorized
    case subscriptionInactive
    case notFound

    var errorDescription: String? {
        switch self {
        case .serverError(let code):  return "Server error (HTTP \(code))"
        case .invalidResponse:        return "Invalid response from server"
        case .unauthorized:           return "Unauthorized — check EMPY_BACKEND_TOKEN"
        case .subscriptionInactive:   return "Subscription inactive (402)"
        case .notFound:               return "Not found (404)"
        }
    }
}
