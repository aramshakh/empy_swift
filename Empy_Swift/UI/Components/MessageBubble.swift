//
//  MessageBubble.swift
//  Empy_Swift
//
//  Created by AI Agent on 2026-03-19.
//  Message bubble for agent chat
//

import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            // User messages: right-aligned
            if !message.isAgent {
                Spacer()
            }
            
            VStack(alignment: message.isAgent ? .leading : .trailing, spacing: 4) {
                // Message text
                Text(message.text)
                    .padding(12)
                    .background(
                        message.isAgent
                            ? Color.gray.opacity(0.2)
                            : Color.blue.opacity(0.7)
                    )
                    .foregroundColor(message.isAgent ? .primary : .white)
                    .cornerRadius(12)
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Agent messages: left-aligned
            if message.isAgent {
                Spacer()
            }
        }
    }
}

// MARK: - Preview

struct MessageBubble_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Agent message
            MessageBubble(
                message: ChatMessage(
                    id: UUID(),
                    text: "Hi! Call started. What do you want to focus on?",
                    isAgent: true,
                    timestamp: Date()
                )
            )
            
            // User message
            MessageBubble(
                message: ChatMessage(
                    id: UUID(),
                    text: "What should I ask about pricing?",
                    isAgent: false,
                    timestamp: Date()
                )
            )
        }
        .padding()
        .frame(width: 400)
    }
}
