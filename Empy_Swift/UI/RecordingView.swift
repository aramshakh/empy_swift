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
    @EnvironmentObject var conversationManager: ConversationManager
    @State private var isPaused: Bool = false
    @State private var transcriptMessages: [TranscriptMessage] = []
    @State private var cancellables = Set<AnyCancellable>()
    
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
                ForEach(conversationManager.coachCards) { card in
                    CoachCardView(card: card) {
                        conversationManager.dismissCard(card)
                    }
                }
            }
            .frame(width: 350)
            .padding(EmpySpacing.lg)
        }
        .onAppear {
            setupObservers()
            startRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    // MARK: - Setup & Observers
    
    private func setupObservers() {
        // Observe transcript updates from shared TranscriptEngine
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
    
    // MARK: - Sidebar
    
    private func sidebarView() -> some View {
        VStack(alignment: .leading, spacing: EmpySpacing.md) {
            // Session timer at top
            SessionTimerView()
            
            // Talk ratio indicator (real data from API, defaults to 0.5 until data arrives)
            TalkRatioView(userPercentage: conversationManager.speakingRatioMe)
            
            Divider()
            
            Text("Session Stats")
                .font(.empyLabel)
                .foregroundColor(.empySecondaryText)
            
            if let stats = conversationManager.latestStatistics,
               let ratio = stats.speakingRatio {
                VStack(alignment: .leading, spacing: EmpySpacing.xs) {
                    ForEach(Array(ratio.speakers.sorted(by: { $0.key < $1.key })), id: \.key) { speaker, pct in
                        statsRow(label: speaker, value: "\(Int(pct * 100))%")
                    }
                }
            } else {
                Text("Waiting for data…")
                    .font(.empyCaption)
                    .foregroundColor(.empySecondaryText)
            }
            
            Divider()
            
            Text("Coach Cards")
                .font(.empyLabel)
                .foregroundColor(.empySecondaryText)
            
            let cardCount = conversationManager.coachCards.count
            Text(cardCount == 0 ? "No cards yet" : "\(cardCount) active")
                .font(.empyCaption)
                .foregroundColor(.empySecondaryText)
            
            if conversationManager.isProcessing {
                HStack(spacing: EmpySpacing.xs) {
                    ProgressView().scaleEffect(0.6)
                    Text("Analyzing…")
                        .font(.empyCaption)
                        .foregroundColor(.empySecondaryText)
                }
            }
            
            Spacer()
        }
        .padding(EmpySpacing.md)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func statsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.empyCaption)
                .foregroundColor(.empySecondaryText)
            Spacer()
            Text(value)
                .font(.empyCaption)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Transcript Area
    
    private func transcriptAreaView() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: EmpySpacing.sm) {
                    ForEach(transcriptMessages) { message in
                        TranscriptMessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding(EmpySpacing.md)
            }
            .onChange(of: transcriptMessages.count) { _ in
                // Auto-scroll to bottom when new message arrives
                if let lastMessage = transcriptMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Control Bar
    
    private func controlBarView() -> some View {
        HStack(spacing: EmpySpacing.md) {
            Button {
                sessionManager.stopRecording()
                let finalTranscript = transcriptEngine.transcriptState.fullText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                coordinator.endRecording(
                    transcript: finalTranscript.isEmpty ? "No transcript captured" : finalTranscript
                )
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
    
}

#Preview {
    NavigationStack {
        RecordingView()
            .environmentObject(NavigationCoordinator())
    }
}
