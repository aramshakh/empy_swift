//
//  RecordingView.swift
//  Empy_Swift
//
//  T11: Recording screen layout
//  T16: Full audio integration
//

import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var isPaused: Bool = false
    @State private var transcriptMessages: [TranscriptMessage] = []
    
    // T16: Audio integration components
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var deepgramClient = DeepgramClient()
    @StateObject private var transcriptEngine = TranscriptEngine()
    
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
    
    // MARK: - Sidebar
    
    private func sidebarView() -> some View {
        VStack(alignment: .leading, spacing: EmpySpacing.md) {
            // Session timer at top
            SessionTimerView()
            
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
                stopRecording()
                coordinator.endRecording(transcript: generateTranscriptText())
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
    
    // MARK: - Audio Pipeline (T16)
    
    private func setupAudioPipeline() {
        // 1. AudioEngine → DeepgramClient
        audioEngine.onChunkReady = { audioData in
            deepgramClient.send(audioData)
        }
        
        // 2. DeepgramClient → TranscriptEngine
        deepgramClient.onTranscriptionReceived = { result in
            transcriptEngine.addTranscript(
                text: result.channel.alternatives.first?.transcript ?? "",
                isFinal: result.isFinal,
                speaker: .you  // TODO: speaker diarization in future
            )
        }
        
        // 3. TranscriptEngine → UI
        transcriptEngine.onMessageAdded = { message in
            DispatchQueue.main.async {
                if let index = transcriptMessages.firstIndex(where: { $0.id == message.id }) {
                    // Update existing (interim → final)
                    transcriptMessages[index] = message
                } else {
                    // Add new
                    transcriptMessages.append(message)
                }
            }
        }
    }
    
    private func startRecording() {
        Task {
            do {
                // Request mic permission
                let granted = await audioEngine.requestPermission()
                guard granted else {
                    print("⚠️ Microphone permission denied")
                    return
                }
                
                // Connect Deepgram
                try await deepgramClient.connect()
                
                // Start audio capture
                try audioEngine.startRecording()
                
                print("✅ Recording started successfully")
            } catch {
                print("❌ Failed to start recording: \(error)")
            }
        }
    }
    
    private func stopRecording() {
        audioEngine.stopRecording()
        deepgramClient.disconnect()
        print("🛑 Recording stopped")
    }
    
    private func generateTranscriptText() -> String {
        transcriptMessages
            .filter { $0.isFinal }
            .map { $0.text }
            .joined(separator: " ")
    }
}

#Preview {
    NavigationStack {
        RecordingView()
            .environmentObject(NavigationCoordinator())
    }
}
