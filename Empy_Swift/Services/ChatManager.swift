//
//  ChatManager.swift
//  Empy_Swift
//
//  Created by AI Agent on 2026-03-19.
//  Business logic for real-time agent chat
//

import Foundation
import Combine

/// Manages agent chat messages and API communication
class ChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    
    private let apiClient: BackendAPIClient
    private var conversationId: String?
    
    init(apiClient: BackendAPIClient = .shared) {
        self.apiClient = apiClient
    }
    
    // MARK: - Initialize
    
    /// Initialize chat with conversation ID and greeting
    func initialize(conversationId: String) {
        self.conversationId = conversationId
        
        // Initial greeting
        addAgentMessage("Hi! Call started. What do you want to focus on?")
    }
    
    // MARK: - Send Message
    
    /// Send user message and get agent response
    func sendMessage() {
        guard !inputText.isEmpty else { return }
        guard let convId = conversationId else {
            print("ChatManager: No conversation ID set")
            return
        }
        
        let userText = inputText
        addUserMessage(userText)
        inputText = ""
        
        // Create nudge for user query
        let nudge = Nudge(
            conversationId: convId,
            text: userText,
            type: "user_query"
        )
        
        Task {
            await getAdvice(nudge: nudge)
        }
    }
    
    // MARK: - Handle Detected Question
    
    /// Handle auto-detected question from transcript
    func handleDetectedQuestion(_ questionText: String) {
        guard let convId = conversationId else {
            print("ChatManager: No conversation ID for detected question")
            return
        }
        
        // Create nudge for question help
        let nudge = Nudge(
            conversationId: convId,
            text: questionText,
            type: "question_help"
        )
        
        Task {
            await getAdvice(nudge: nudge)
        }
    }
    
    // MARK: - Get Advice (Private)
    
    private func getAdvice(nudge: Nudge) async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let request = AdviceRequest(nudge: nudge)
            let response = try await apiClient.getAdvice(request: request)
            
            await MainActor.run {
                addAgentMessage(response.text)
                isLoading = false
            }
        } catch let error as APIError {
            print("ChatManager: API error - \(error.localizedDescription)")
            
            await MainActor.run {
                addAgentMessage("❌ \(error.localizedDescription)")
                isLoading = false
            }
        } catch {
            print("ChatManager: Unexpected error - \(error)")
            
            await MainActor.run {
                addAgentMessage("❌ Connection error")
                isLoading = false
            }
        }
    }
    
    // MARK: - Add Messages
    
    private func addUserMessage(_ text: String) {
        let message = ChatMessage(
            id: UUID(),
            text: text,
            isAgent: false,
            timestamp: Date()
        )
        messages.append(message)
    }
    
    private func addAgentMessage(_ text: String) {
        let message = ChatMessage(
            id: UUID(),
            text: text,
            isAgent: true,
            timestamp: Date()
        )
        messages.append(message)
    }
    
    // MARK: - Reset
    
    /// Reset chat state (for new conversation)
    func reset() {
        messages.removeAll()
        conversationId = nil
        inputText = ""
        isLoading = false
    }
}

// MARK: - ChatMessage Model

struct ChatMessage: Identifiable {
    let id: UUID
    let text: String
    let isAgent: Bool
    let timestamp: Date
}
