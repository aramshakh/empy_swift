//
//  TranscriptMessageView.swift
//  Empy_Swift
//
//  iMessage-style chat bubble: you → right (blue), participant → left (gray)
//

import SwiftUI

struct TranscriptMessageView: View {
    let message: TranscriptMessage
    
    private var isYou: Bool { message.speaker == .you }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isYou { Spacer(minLength: 48) }
            
            VStack(alignment: isYou ? .trailing : .leading, spacing: 2) {
                // Speaker label (only for participant)
                if !isYou {
                    Text(speakerLabel)
                        .font(.empyCaption)
                        .foregroundColor(.empySecondaryText)
                        .padding(.leading, 4)
                }
                
                // Bubble
                HStack(spacing: 4) {
                    if !message.isFinal {
                        // Typing indicator dots for partial
                        Text("…")
                            .font(.empyCaption)
                            .foregroundColor(isYou ? .white.opacity(0.7) : .secondary)
                    }
                    Text(message.text)
                        .font(.empyBody)
                        .foregroundColor(isYou ? .white : .primary)
                        .multilineTextAlignment(isYou ? .trailing : .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleColor)
                .clipShape(BubbleShape(isYou: isYou))
                .opacity(message.isFinal ? 1.0 : 0.75)
                
                // Timestamp
                Text(timeString)
                    .font(.empyCaption)
                    .foregroundColor(.empySecondaryText)
                    .padding(isYou ? .trailing : .leading, 4)
            }
            
            if !isYou { Spacer(minLength: 48) }
        }
        .padding(.vertical, 2)
    }
    
    private var bubbleColor: Color {
        isYou ? Color.empySpeakerYou : Color(NSColor.tertiaryLabelColor).opacity(0.15)
    }
    
    private var speakerLabel: String {
        switch message.speaker {
        case .you: return "You"
        case .participant(let name): return name.isEmpty ? "Participant" : name
        }
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: message.timestamp)
    }
}

/// Rounded rect with one sharp corner (iMessage style)
private struct BubbleShape: Shape {
    let isYou: Bool
    
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16
        let sharpR: CGFloat = 4
        
        // Corners: topLeft, topRight, bottomRight, bottomLeft
        let tl: CGFloat = isYou ? r : sharpR
        let tr: CGFloat = isYou ? sharpR : r
        let br: CGFloat = r
        let bl: CGFloat = r
        
        var path = Path()
        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: rect.width - tr, y: 0))
        path.addArc(center: CGPoint(x: rect.width - tr, y: tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - br))
        path.addArc(center: CGPoint(x: rect.width - br, y: rect.height - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: bl, y: rect.height))
        path.addArc(center: CGPoint(x: bl, y: rect.height - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: EmpySpacing.sm) {
        TranscriptMessageView(
            message: TranscriptMessage(
                id: UUID(),
                speaker: .you,
                text: "Hey, thanks for taking the call",
                timestamp: Date(),
                isFinal: true
            )
        )
        TranscriptMessageView(
            message: TranscriptMessage(
                id: UUID(),
                speaker: .participant(name: "Speaker 1"),
                text: "No problem, happy to chat",
                timestamp: Date().addingTimeInterval(4),
                isFinal: true
            )
        )
        TranscriptMessageView(
            message: TranscriptMessage(
                id: UUID(),
                speaker: .you,
                text: "typing something right now",
                timestamp: Date().addingTimeInterval(8),
                isFinal: false
            )
        )
    }
    .padding()
    .frame(width: 500)
}
