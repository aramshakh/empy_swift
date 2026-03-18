//
//  RecordingView.swift
//  Empy_Swift
//
//  T11: Recording screen layout
//  T16: Audio integration with corrected API calls
//

import SwiftUI
import Combine

struct RecordingView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var transcriptEngine: TranscriptEngine
    @State private var isPaused: Bool = false
    @State private var transcriptMessages: [TranscriptMessage] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var coachCards: [CoachCard] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content: Sidebar + Transcript
            HSplitView {
                // Left sidebar
                sidebarView()
                    .frame(width: 280)
                
                // Main transcript area
                transcriptAreaView()
            }
            
            // Bottom control bar
            controlBarView()
        }
        .navigationTitle("Recording")
        .overlay(alignment: .topTrailing) {
            VStack(spacing: EmpySpacing.md) {
                ForEach(coachCards) { card in
                    CoachCardView(card: card) {
                        coachCards.removeAll { $0.id == card.id }
                    }
                }
            }
            .frame(width: 350)
            .padding(EmpySpacing.lg)
        }
        .onAppear {
            // Clear ALL state synchronously before async work starts —
            // prevents last sentence of previous session leaking into new one
            transcriptMessages = []
            coachCards = []
            isPaused = false
            transcriptEngine.clearState()
            cancellables.removeAll()
            setupObservers()
            startRecording()
            
            // Test: show card after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                addMockCoachCard()
            }
        }
        .onDisappear {
            cancellables.removeAll()
            stopRecording()
        }
    }
    
    // MARK: - Setup & Observers
    
    private func setupObservers() {
        // Mirror TranscriptEngine segments directly — accumulation logic
        // is handled in TranscriptEngine (20s bubbles), UI just renders
        transcriptEngine.$transcriptState
            .receive(on: DispatchQueue.main)
            .sink { state in
                transcriptMessages = state.segments.map { segment in
                    TranscriptMessage(
                        id: segment.id,
                        speaker: segment.speaker.flatMap { .participant(name: $0) } ?? .you,
                        text: segment.text,
                        timestamp: segment.timestamp,
                        isFinal: segment.isFinal
                    )
                }
            }
            .store(in: &cancellables)
    }
    
    private func startRecording() {
        Task {
            do {
                try sessionManager.startRecording()
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    private func stopRecording() {
        sessionManager.stopRecording()
    }
    
    // MARK: - Talk Ratio Calculation
    
    private func calculateTalkRatio() -> Double {
        let messages = transcriptEngine.transcriptState.segments
        guard !messages.isEmpty else { return 0.5 }
        
        let userWords = messages
            .filter { $0.speaker == "you" }
            .reduce(0) { $0 + $1.text.split(separator: " ").count }
        
        let totalWords = messages
            .reduce(0) { $0 + $1.text.split(separator: " ").count }
        
        guard totalWords > 0 else { return 0.5 }
        return Double(userWords) / Double(totalWords)
    }
    
    // MARK: - Sidebar
    
    private func sidebarView() -> some View {
        VStack(alignment: .leading, spacing: EmpySpacing.md) {
            // Session timer at top
            SessionTimerView()
            
            // Talk ratio indicator
            TalkRatioView(userPercentage: calculateTalkRatio())
            
            Divider()
            
            Text("Session Stats")
                .font(.empyLabel)
                .foregroundColor(.empySecondaryText)
            
            Text("Stats placeholder")
                .font(.empyCaption)
            
            Divider()
            
            Text("Coach Cards")
                .font(.empyLabel)
                .foregroundColor(.empySecondaryText)
            
            Text("Coach cards placeholder")
                .font(.empyCaption)
            
            Spacer()
        }
        .padding(EmpySpacing.md)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Transcript Area
    
    private func transcriptAreaView() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Alignment is handled inside each TranscriptMessageView (iMessage style)
                LazyVStack(spacing: EmpySpacing.xs) {
                    ForEach(transcriptMessages) { message in
                        TranscriptMessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding(EmpySpacing.md)
            }
            .onChange(of: transcriptMessages.count) { _ in
                if let lastMessage = transcriptMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            // Also scroll when the last bubble's text updates (partial growing)
            .onChange(of: transcriptMessages.last?.text) { _ in
                if let lastMessage = transcriptMessages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Control Bar
    
    private func controlBarView() -> some View {
        HStack(spacing: EmpySpacing.md) {
            Button {
                // Snapshot messages BEFORE stopping — stopRecording() disconnects
                // Deepgram and pending async segment mutations may not have fired yet
                let finalMessages = transcriptEngine.transcriptState.segments.map { segment in
                    TranscriptMessage(
                        id: segment.id,
                        speaker: segment.speaker,
                        text: segment.text,
                        timestamp: segment.startTime,
                        isFinal: segment.isFinal
                    )
                }
                sessionManager.stopRecording()
                coordinator.endRecording(messages: finalMessages)
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            
            Button {
                if isPaused {
                    try? sessionManager.resumeRecording()
                } else {
                    sessionManager.pauseRecording()
                }
                isPaused.toggle()
            } label: {
                HStack {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    Text(isPaused ? "Resume" : "Pause")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(EmpySpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Mock Coach Cards (for testing)
    
    private func addMockCoachCard() {
        let mockCards: [(CoachCardType, String, String)] = [
            (.warning, "Speaking too fast", "Try to slow down for clarity"),
            (.tip, "Ask open questions", "Open-ended questions encourage dialogue"),
            (.insight, "Good balance", "You're maintaining balanced talk time")
        ]
        
        let random = mockCards.randomElement()!
        let card = CoachCard(type: random.0, title: random.1, message: random.2)
        coachCards.append(card)
        
        // Auto-dismiss after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            coachCards.removeAll { $0.id == card.id }
        }
    }
}

#Preview {
    NavigationStack {
        RecordingView()
            .environmentObject(NavigationCoordinator())
    }
}
