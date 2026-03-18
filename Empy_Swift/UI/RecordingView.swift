//
//  RecordingView.swift
//  Empy_Swift
//
//  T11: Recording screen layout
//  T16: Audio integration with corrected API calls
//

import SwiftUI
import Combine

enum RecordingTab { case transcript, agent }

struct RecordingView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var transcriptEngine: TranscriptEngine
    @State private var isPaused: Bool = false
    @State private var transcriptMessages: [TranscriptMessage] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var coachCards: [CoachCard] = []
    @State private var selectedTab: RecordingTab = .transcript
    @State private var showAudioSettings: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Main content: Sidebar + tabbed area
            HSplitView {
                // Left sidebar
                sidebarView()
                    .frame(width: 280)

                // Right: tab picker + content
                VStack(spacing: 0) {
                    tabPickerView()
                    Divider()
                    tabContentView()
                }
            }

            // Bottom control bar
            controlBarView()
        }
        .navigationTitle("Recording")
        .onAppear {
            transcriptMessages = []
            coachCards = []
            isPaused = false
            selectedTab = .transcript
            transcriptEngine.clearState()
            cancellables.removeAll()
            setupObservers()
            startRecording()
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
                        speaker: Self.speakerFrom(segment.speaker),
                        text: segment.text,
                        timestamp: segment.timestamp,
                        isFinal: segment.isFinal
                    )
                }
            }
            .store(in: &cancellables)
    }
    
    private func startRecording() {
        sessionManager.startRecording()
    }
    
    private func stopRecording() {
        sessionManager.stopRecording()
    }
    
    // MARK: - Speaker mapping
    
    /// Maps a segment's speaker String? ("you" / "Other" / nil) to the Speaker enum.
    /// "you" → .you (right bubble, blue)
    /// anything else → .participant (left bubble, gray)
    private static func speakerFrom(_ speaker: String?) -> Speaker {
        guard let s = speaker, !s.isEmpty else { return .you }
        return s.lowercased() == "you" ? .you : .participant(name: s)
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
            
            Spacer()

            Divider()

            // Gear button → AudioSettings popover
            Button {
                showAudioSettings.toggle()
            } label: {
                HStack(spacing: EmpySpacing.xs) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                        .font(.empyCaption)
                }
                .foregroundColor(.empySecondaryText)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAudioSettings, arrowEdge: .trailing) {
                AudioSettingsView(isInSession: true)
                    .padding()
                    .frame(width: 300)
            }
        }
        .padding(EmpySpacing.md)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Tab picker

    private func tabPickerView() -> some View {
        HStack(spacing: 0) {
            tabButton(title: "Transcript", tab: .transcript)
            tabButton(title: "Agent", tab: .agent, badge: coachCards.count)
        }
        .padding(.horizontal, EmpySpacing.md)
        .padding(.top, EmpySpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func tabButton(title: String, tab: RecordingTab, badge: Int = 0) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.empyLabel)
                    .fontWeight(isSelected ? .semibold : .regular)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, EmpySpacing.sm)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab content

    @ViewBuilder
    private func tabContentView() -> some View {
        switch selectedTab {
        case .transcript:
            transcriptAreaView()
        case .agent:
            AgentFeedView(cards: coachCards)
        }
    }

    // MARK: - Transcript Area

    private func transcriptAreaView() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
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
                        speaker: Self.speakerFrom(segment.speaker),
                        text: segment.text,
                        timestamp: segment.timestamp,
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
                    sessionManager.resumeRecording()
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
