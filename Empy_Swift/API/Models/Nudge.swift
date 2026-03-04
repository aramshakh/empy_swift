//
//  Nudge.swift
//  Empy_Swift
//
//  Maps API NudgeDTO to CoachCard for UI display
//

import Foundation

extension NudgeDTO {
    /// Convert an API nudge to a CoachCard for display
    func toCoachCard() -> CoachCard {
        let cardType: CoachCardType
        switch severity {
        case "negative":
            cardType = .warning
        case "positive":
            cardType = .insight
        default:
            cardType = .tip
        }
        
        let title: String
        switch type {
        case "engagement_check": title = "Engagement"
        case "risk_check":       title = "Risk Alert"
        case "emotion_check":    title = "Emotional Signal"
        case "focus_check":      title = "Focus"
        default:                 title = "Coach"
        }
        
        return CoachCard(
            type: cardType,
            title: title,
            message: text,
            nudgeId: nudgeId,
            conversationId: conversationId
        )
    }
}
