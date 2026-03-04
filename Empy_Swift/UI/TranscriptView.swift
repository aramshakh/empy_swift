//
//  TranscriptView.swift
//  Empy_Swift
//
//  Created by Subagent on 2026-03-04.
//  Real-time scrolling transcript display
//

import SwiftUI

struct TranscriptView: View {
    @ObservedObject var transcriptEngine: TranscriptEngine
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcriptEngine.transcriptState.segments) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            // Speaker label
                            if let speaker = segment.speaker {
                                Text(speaker)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Text
                            Text(segment.text)
                                .font(.body)
                                .foregroundColor(segment.isFinal ? .primary : .secondary)
                        }
                        .id(segment.id)
                    }
                }
                .padding()
            }
            .onChange(of: transcriptEngine.transcriptState.segments.count) { _ in
                // Auto-scroll to bottom
                if let lastId = transcriptEngine.transcriptState.segments.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Preview

// Preview removed - requires live DeepgramClient initialization
