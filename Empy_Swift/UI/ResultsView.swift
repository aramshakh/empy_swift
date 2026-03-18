//
//  ResultsView.swift
//  Empy_Swift
//
//  Post-call dialogue report: full transcript as readable iMessage-style conversation
//

import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    let messages: [TranscriptMessage]
    
    // MARK: - Computed stats
    
    private var youMessages: [TranscriptMessage] {
        messages.filter { $0.speaker == .you }
    }
    
    private var otherMessages: [TranscriptMessage] {
        messages.filter { $0.speaker != .you }
    }
    
    private var youWordCount: Int {
        youMessages.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }
    
    private var otherWordCount: Int {
        otherMessages.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }
    
    private var totalWordCount: Int { youWordCount + otherWordCount }
    
    private var youPercent: Int {
        guard totalWordCount > 0 else { return 50 }
        return Int(Double(youWordCount) / Double(totalWordCount) * 100)
    }
    
    var body: some View {
        HSplitView {
            // Left: dialogue transcript
            transcriptColumn
                .frame(minWidth: 400)
            
            // Right: stats panel
            statsColumn
                .frame(width: 260)
        }
        .navigationTitle("Session Results")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Session") {
                    coordinator.startNewSession()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Transcript column
    
    private var transcriptColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Conversation Transcript")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("\(messages.count) messages · \(totalWordCount) words")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            Divider()
            
            if messages.isEmpty {
                Spacer()
                Text("No transcript captured")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            ResultsMessageRow(message: message, index: index + 1)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Stats column
    
    private var statsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Session Stats")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.top, 20)
                
                // Talk ratio bar
                VStack(alignment: .leading, spacing: 8) {
                    Text("Talk Ratio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * CGFloat(youPercent) / 100)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.purple.opacity(0.6))
                        }
                        .frame(height: 12)
                    }
                    .frame(height: 12)
                    
                    HStack {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("You \(youPercent)%").font(.caption)
                        Spacer()
                        Circle().fill(Color.purple.opacity(0.6)).frame(width: 8, height: 8)
                        Text("Other \(100 - youPercent)%").font(.caption)
                    }
                }
                
                Divider()
                
                // Message counts
                statRow(label: "Your messages", value: "\(youMessages.count)")
                statRow(label: "Other messages", value: "\(otherMessages.count)")
                statRow(label: "Your words", value: "\(youWordCount)")
                statRow(label: "Other words", value: "\(otherWordCount)")
                statRow(label: "Total words", value: "\(totalWordCount)")
                
                Divider()
                
                // Export button
                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
    
    private func copyToClipboard() {
        let text = messages.map { msg in
            let speaker: String
            switch msg.speaker {
            case .you: speaker = "You"
            case .participant(let name): speaker = name.isEmpty ? "Other" : name
            }
            let time = DateFormatter.shortTime.string(from: msg.timestamp)
            return "[\(time)] \(speaker): \(msg.text)"
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Single message row in results

private struct ResultsMessageRow: View {
    let message: TranscriptMessage
    let index: Int
    
    private var isYou: Bool { message.speaker == .you }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Message number
            Text("\(index)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)
                .padding(.top, 3)
            
            // Speaker avatar dot
            Circle()
                .fill(isYou ? Color.blue : Color.purple.opacity(0.7))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(speakerLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isYou ? .blue : .purple)
                    Text(DateFormatter.shortTime.string(from: message.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(message.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isYou ? Color.blue.opacity(0.03) : Color.clear)
    }
    
    private var speakerLabel: String {
        switch message.speaker {
        case .you: return "You"
        case .participant(let name): return name.isEmpty ? "Other" : name
        }
    }
}

// MARK: - Helpers

private extension DateFormatter {
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

#Preview {
    let messages: [TranscriptMessage] = [
        TranscriptMessage(id: UUID(), speaker: .you,
                          text: "Hey, thanks for taking the call today.",
                          timestamp: Date(), isFinal: true),
        TranscriptMessage(id: UUID(), speaker: .participant(name: "Other"),
                          text: "Of course, happy to chat. What's on your mind?",
                          timestamp: Date().addingTimeInterval(5), isFinal: true),
        TranscriptMessage(id: UUID(), speaker: .you,
                          text: "I wanted to discuss the Q3 roadmap and make sure we're aligned on priorities.",
                          timestamp: Date().addingTimeInterval(12), isFinal: true),
        TranscriptMessage(id: UUID(), speaker: .participant(name: "Other"),
                          text: "Absolutely. I think the main priorities should be performance and reliability.",
                          timestamp: Date().addingTimeInterval(20), isFinal: true),
    ]
    NavigationStack {
        ResultsView(messages: messages)
            .environmentObject(NavigationCoordinator())
    }
    .frame(width: 800, height: 600)
}
