//
//  EmpyAPIModels.swift
//  Empy_Swift
//
//  Codable request/response models for the Empy backend API
//

import Foundation

// MARK: - Health Check

struct HealthResponse: Codable {
    let status: String
    let version: String
}

// MARK: - POST /conversation

struct CreateConversationRequest: Codable {
    let userId: String
    let agenda: String
    let meetingInfo: MeetingInfo
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case agenda
        case meetingInfo = "meeting_info"
    }
}

struct MeetingInfo: Codable {
    let goal: String
    let duration: Int
    let participantContext: String
    
    enum CodingKeys: String, CodingKey {
        case goal, duration
        case participantContext = "participant_context"
    }
}

struct CreateConversationResponse: Codable {
    let conversationId: String
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
    }
}

// MARK: - POST /process

struct ProcessRequest: Codable {
    let id: String
    let conversation: [ConversationEntry]
    let debug: Bool
}

struct ConversationEntry: Codable, Hashable {
    let id: Int
    let text: String
    let timeStart: Double
    let timeEnd: Double
    let speaker: String
    let type: String?
    
    enum CodingKeys: String, CodingKey {
        case id, text
        case timeStart = "time_start"
        case timeEnd = "time_end"
        case speaker, type
    }
}

struct ProcessResponse: Codable {
    let nudges: [NudgeDTO]
    let statistics: ConversationStatistics?
    let needs: [String]?
    let feelings: [String]?
}

struct NudgeDTO: Codable, Identifiable {
    let conversationId: String
    let text: String
    let nudgeId: String
    let timestamp: Double
    let type: String
    let severity: String?
    
    var id: String { nudgeId }
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case text
        case nudgeId = "nudge_id"
        case timestamp, type, severity
    }
}

struct ConversationStatistics: Codable {
    let speakingRatio: SpeakingRatio?
    let evaluationVsFactual: EvaluationVsFactual?
    
    enum CodingKeys: String, CodingKey {
        case speakingRatio = "speaking_ratio"
        case evaluationVsFactual = "evaluation_vs_factual"
    }
}

struct SpeakingRatio: Codable {
    let speakers: [String: Double]
}

struct EvaluationVsFactual: Codable {
    let factualStatements: [String: Int]?
    let evaluativeStatements: [String: Int]?
    
    enum CodingKeys: String, CodingKey {
        case factualStatements = "factual_statements"
        case evaluativeStatements = "evaluative_statements"
    }
}

// MARK: - POST /conversation/{id}/end

struct EndConversationResponse: Codable {
    let conversationId: String
    let summary: ConversationSummary
    let reportId: String
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case summary
        case reportId = "report_id"
    }
}

struct ConversationSummary: Codable, Hashable {
    let agendaCoverage: [AgendaCoverageItem]?
    let takeaways: [String]?
    let actionPoints: [String]?
    
    enum CodingKeys: String, CodingKey {
        case agendaCoverage = "agenda_coverage"
        case takeaways
        case actionPoints = "action_points"
    }
}

struct AgendaCoverageItem: Codable, Hashable, Identifiable {
    let topic: String
    let met: Bool
    
    var id: String { topic }
}

// MARK: - POST /advice

struct AdviceRequest: Codable {
    let nudge: NudgeDTO
}

struct AdviceResponse: Codable {
    let text: String
}
