//
//  RecordingView.swift
//  Empy_Swift
//
//  T11: Recording screen layout
//

import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var isPaused: Bool = false
    @State private var transcriptMessages: [TranscriptMessage] = []
    
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
            loadMockTranscript()
        }
    }
    
    // MARK: - Sidebar
    
    private func sidebarView() -> some View {
        VStack(alignment: .leading, spacing: EmpySpacing.md) {
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
    
    // MARK: - Mock Data
    
    private func loadMockTranscript() {
        // Mock data for testing UI
        transcriptMessages = [
            TranscriptMessage(
                id: UUID(),
                speaker: .you,
                text: "Hey, thanks for taking the call",
                timestamp: Date(),
                isFinal: true
            ),
            TranscriptMessage(
                id: UUID(),
                speaker: .participant(name: "Speaker 1"),
                text: "No problem, happy to chat",
                timestamp: Date().addingTimeInterval(4),
                isFinal: true
            ),
            TranscriptMessage(
                id: UUID(),
                speaker: .you,
                text: "So I wanted to discuss the project timeline",
                timestamp: Date().addingTimeInterval(8),
                isFinal: true
            )
        ]
    }
}

#Preview {
    NavigationStack {
        RecordingView()
            .environmentObject(NavigationCoordinator())
    }
}
