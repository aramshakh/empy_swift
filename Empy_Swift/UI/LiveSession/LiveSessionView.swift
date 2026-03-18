//
//  LiveSessionView.swift
//  Empy_Swift
//
//  T11: Live Session View Container
//  Main container for live recording session with timer and controls.
//

import SwiftUI

struct LiveSessionView: View {
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var transcriptEngine: TranscriptEngine
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header (Timer)
            HStack {
                Text(formatElapsed(sessionManager.elapsed))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Spacer()
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // MARK: - Transcript
            TranscriptContentView(transcriptEngine: transcriptEngine)
            
            Divider()
            
            // MARK: - Controls
            HStack(spacing: 16) {
                Button(action: {
                    Task {
                        await sessionManager.stopRecording()
                    }
                }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                Button(action: {
                    if sessionManager.state == .recording {
                        sessionManager.pauseRecording()
                    } else {
                        try? sessionManager.resumeRecording()
                    }
                }) {
                    Label(
                        sessionManager.state == .recording ? "Pause" : "Resume",
                        systemImage: sessionManager.state == .recording ? "pause.fill" : "play.fill"
                    )
                    .frame(width: 120)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .onAppear {
            if sessionManager.state == .idle {
                Task {
                    try? await sessionManager.startRecording()
                }
            }
        }
        .onDisappear {
            if sessionManager.state == .recording {
                Task {
                    await sessionManager.stopRecording()
                }
            }
        }
    }
    
    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

// MARK: - Transcript Content View (Placeholder)

/// Displays transcript content.
/// This will be replaced by TranscriptView (T12) when available.
private struct TranscriptContentView: View {
    @ObservedObject var transcriptEngine: TranscriptEngine
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(transcriptEngine.transcriptState.segments) { segment in
                    HStack(alignment: .top) {
                        Text(segment.text)
                            .font(.body)
                            .foregroundColor(segment.isFinal ? .primary : .secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                if transcriptEngine.transcriptState.segments.isEmpty {
                    Text("Waiting for speech...")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Preview

struct LiveSessionView_Previews: PreviewProvider {
    static var previews: some View {
        LiveSessionView(
            sessionManager: SessionManager.shared,
            transcriptEngine: SessionManager.shared.transcript
        )
        .frame(width: 600, height: 800)
    }
}
