import Foundation
import SwiftUI

enum CoachCardType {
    case warning
    case tip
    case insight
    
    var icon: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .tip: return "lightbulb.fill"
        case .insight: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .warning: return .red
        case .tip: return .blue
        case .insight: return .green
        }
    }
}

struct CoachCard: Identifiable {
    let id: UUID
    let type: CoachCardType
    let title: String
    let message: String
    let timestamp: Date
    let nudgeId: String?
    let conversationId: String?
    
    init(type: CoachCardType, title: String, message: String,
         nudgeId: String? = nil, conversationId: String? = nil) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.message = message
        self.timestamp = Date()
        self.nudgeId = nudgeId
        self.conversationId = conversationId
    }
}
