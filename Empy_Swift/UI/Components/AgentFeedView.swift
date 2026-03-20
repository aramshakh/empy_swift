//
//  AgentFeedView.swift
//  Empy_Swift
//
//  Real-time agent feed: coach cards displayed as a chronological list
//  (not pop-ups). Lives in the "Agent" tab of RecordingView.
//

import SwiftUI

struct AgentFeedView: View {
    let cards: [CoachCard]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if cards.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: EmpySpacing.sm) {
                        ForEach(cards) { card in
                            AgentFeedRow(card: card)
                                .id(card.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .padding(EmpySpacing.md)
                }
            }
            .onChange(of: cards.count) { _ in
                if let last = cards.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: EmpySpacing.md) {
            Image(systemName: "brain")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Agent insights will appear here")
                .font(.empyBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Individual feed row (no dismiss button — it's a log, not a toast)

private struct AgentFeedRow: View {
    let card: CoachCard

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: card.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: EmpySpacing.md) {
            // Colored icon
            Image(systemName: card.type.icon)
                .foregroundColor(card.type.color)
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.title)
                        .font(.empyLabel)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(timeString)
                        .font(.empyCaption)
                        .foregroundColor(.secondary)
                }
                Text(card.message)
                    .font(.empyCaption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EmpySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: EmpyRadius.md)
                .fill(card.type.color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: EmpyRadius.md)
                        .strokeBorder(card.type.color.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    AgentFeedView(cards: [
        CoachCard(type: .warning, title: "Speaking too fast",
                  message: "Try to slow down your speech for better clarity"),
        CoachCard(type: .tip,     title: "Ask open questions",
                  message: "Open-ended questions lead to richer conversations"),
        CoachCard(type: .insight, title: "Good balance",
                  message: "You're maintaining a healthy talk ratio so far"),
    ])
    .frame(width: 480, height: 400)
}
