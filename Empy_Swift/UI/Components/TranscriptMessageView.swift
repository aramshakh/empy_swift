//
//  TranscriptMessageView.swift
//  Empy_Swift
//
//  T12: Individual transcript message row
//

import SwiftUI

struct TranscriptMessageView: View {
    let message: TranscriptMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.xs) {
            // Header: Speaker + timestamp
            HStack(spacing: EmpySpacing.xs) {
                Text(speakerLabel)
                    .font(.empyCaption)
                    .foregroundColor(speakerColor)
                    .fontWeight(.semibold)
                
                Text("•")
                    .font(.empyCaption)
                    .foregroundColor(.empySecondaryText)
                
                Text(timeString)
                    .font(.empyCaption)
                    .foregroundColor(.empySecondaryText)
            }
            
            // Message text
            Text(message.text)
                .font(.empyBody)
                .foregroundColor(.primary)
                .opacity(message.isFinal ? 1.0 : 0.6)
        }
        .padding(.vertical, EmpySpacing.xs)
        .padding(.horizontal, EmpySpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: EmpyRadius.sm)
                .fill(message.speaker == .you ? Color.blue.opacity(0.05) : Color.gray.opacity(0.05))
        )
    }
    
    private var speakerLabel: String {
        switch message.speaker {
        case .you:
            return "You"
        case .participant(let name):
            return name
        }
    }
    
    private var speakerColor: Color {
        message.speaker == .you ? .blue : .purple
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        return formatter.string(from: message.timestamp)
    }
}

#Preview {
    VStack(spacing: EmpySpacing.sm) {
        TranscriptMessageView(
            message: TranscriptMessage(
                id: UUID(),
                speaker: .you,
                text: "Hey, thanks for taking the call",
                timestamp: Date(),
                isFinal: true
            )
        )
        
        TranscriptMessageView(
            message: TranscriptMessage(
                id: UUID(),
                speaker: .participant(name: "Speaker 1"),
                text: "No problem, happy to chat",
                timestamp: Date().addingTimeInterval(4),
                isFinal: true
            )
        )
    }
    .padding()
}
