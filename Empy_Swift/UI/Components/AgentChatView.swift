//
//  AgentChatView.swift
//  Empy_Swift
//
//  Created by AI Agent on 2026-03-19.
//  Agent chat interface for real-time coaching
//

import SwiftUI

struct AgentChatView: View {
    @ObservedObject var chatManager: ChatManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages scroll view
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chatManager.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        // Loading indicator
                        if chatManager.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading)
                        }
                    }
                    .padding()
                }
                .onChange(of: chatManager.messages.count) { _ in
                    // Auto-scroll to bottom on new message
                    if let lastMessage = chatManager.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input bar
            HStack(spacing: 12) {
                TextField("Type message...", text: $chatManager.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        chatManager.sendMessage()
                    }
                
                Button {
                    chatManager.sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderedProminent)
                .disabled(chatManager.inputText.isEmpty)
            }
            .padding()
        }
    }
}

// MARK: - Preview

struct AgentChatView_Previews: PreviewProvider {
    static var previews: some View {
        let chatManager = ChatManager()
        chatManager.messages = [
            ChatMessage(id: UUID(), text: "Hi! Call started. What do you want to focus on?", isAgent: true, timestamp: Date()),
            ChatMessage(id: UUID(), text: "What should I ask about pricing?", isAgent: false, timestamp: Date()),
            ChatMessage(id: UUID(), text: "Try asking about their budget and timeline first", isAgent: true, timestamp: Date())
        ]
        
        return AgentChatView(chatManager: chatManager)
            .frame(width: 400, height: 600)
    }
}
