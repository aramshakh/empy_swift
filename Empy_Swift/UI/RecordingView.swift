//
//  RecordingView.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Recording screen placeholder (T09)
//

import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var isRecording = false
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Recording...")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Visual indicator
            Circle()
                .fill(isRecording ? Color.red : Color.gray)
                .frame(width: 100, height: 100)
                .overlay(
                    Circle()
                        .stroke(isRecording ? Color.red.opacity(0.5) : Color.clear, lineWidth: 4)
                        .scaleEffect(isRecording ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isRecording)
                )
            
            Text(isRecording ? "Listening..." : "Paused")
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(isRecording ? "Stop Recording" : "Start Recording") {
                isRecording.toggle()
                
                if !isRecording {
                    // Mock transcript for T09 testing
                    let mockTranscript = """
                    This is a test transcript generated during T09 navigation testing.
                    In production, this will be replaced with real Deepgram transcription.
                    """
                    coordinator.endRecording(transcript: mockTranscript)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(isRecording ? .red : .green)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Recording")
        .onAppear {
            isRecording = true
        }
    }
}

#Preview {
    NavigationStack {
        RecordingView()
            .environmentObject(NavigationCoordinator())
    }
}
