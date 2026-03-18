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
                LazyVStack(spacing: 4) {
                    ForEach(transcriptEngine.transcriptState.segments) { segment in
                        TranscriptMessageView(
                            message: TranscriptMessage(
                                id: segment.id,
                                speaker: speakerFrom(segment.speaker),
                                text: segment.text,
                                timestamp: segment.timestamp,
                                isFinal: segment.isFinal
                            )
                        )
                        .id(segment.id)
                    }
                }
                .padding(EmpySpacing.md)
            }
            .onChange(of: transcriptEngine.transcriptState.segments.count) { _ in
                if let lastId = transcriptEngine.transcriptState.segments.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private func speakerFrom(_ speaker: String?) -> Speaker {
        guard let s = speaker, !s.isEmpty else { return .you }
        return s.lowercased() == "you" ? .you : .participant(name: s)
    }
}

// MARK: - Preview

// Preview removed - requires live DeepgramClient initialization
