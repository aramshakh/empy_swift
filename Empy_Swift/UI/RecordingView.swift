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
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var deepgramClient = DeepgramClient()
    @StateObject private var transcriptEngine = TranscriptEngine()
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
        .onAppear {
            setupAudioPipeline()
            startRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    // MARK: - Audio Pipeline Setup
    
    private func setupAudioPipeline() {
        // 1. AudioEngine → DeepgramClient
        audioEngine.onChunk = { [weak deepgramClient] audioChunk in
            deepgramClient?.send(audioData: audioChunk.data)
        }
        
        // 2. TranscriptEngine observes DeepgramClient internally via delegate
        // Just observe the published state:
        transcriptEngine.$transcriptState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.transcriptMessages = state.segments.map { segment in
                    TranscriptMessage(
                        speaker: .you,
                        text: segment.text,
                        timestamp: Date(),
                        isFinal: segment.isFinal
                    )
                }
            }
            .store(in: &cancellables)
    }
    
    private func startRecording() {
        Task {
            do {
                // TranscriptEngine.startSession() connects Deepgram internally
                transcriptEngine.startSession()
                
                // Start audio capture (handles permission internally)
                try audioEngine.start()
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        transcriptEngine.endSession()
    }
    
    // MARK: - Talk Ratio Calculation
    
    private func calculateTalkRatio() -> Double {
        let messages = transcriptEngine.transcriptState.segments
        guard !messages.isEmpty else { return 0.5 }
        
        let userWords = messages
            .filter { $0.speaker == .you }
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
                coordinator.endRecording(transcript: "Mock transcript from T11")
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
                isPaused.toggle()
                // TODO: implement pause functionality
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
