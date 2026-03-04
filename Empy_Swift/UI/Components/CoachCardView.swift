import SwiftUI

struct CoachCardView: View {
    let card: CoachCard
    let onDismiss: () -> Void
    
    @State private var isVisible = true
    
    var body: some View {
        HStack(alignment: .top, spacing: EmpySpacing.md) {
            // Icon
            Image(systemName: card.type.icon)
                .foregroundColor(card.type.color)
                .font(.system(size: 20))
                .frame(width: 24, height: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.empyLabel)
                    .fontWeight(.semibold)
                
                Text(card.message)
                    .font(.empyCaption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Dismiss button
            Button(action: {
                withAnimation {
                    isVisible = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(EmpySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: EmpyRadius.lg)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.9)
        .animation(.spring(response: 0.3), value: isVisible)
    }
}

#Preview {
    VStack(spacing: 16) {
        CoachCardView(
            card: CoachCard(
                type: .warning,
                title: "Speaking too fast",
                message: "Try to slow down your speech for better clarity"
            ),
            onDismiss: {}
        )
        
        CoachCardView(
            card: CoachCard(
                type: .tip,
                title: "Great question",
                message: "Open-ended questions lead to better conversations"
            ),
            onDismiss: {}
        )
        
        CoachCardView(
            card: CoachCard(
                type: .insight,
                title: "Good listening",
                message: "You're maintaining a balanced talk ratio"
            ),
            onDismiss: {}
        )
    }
    .frame(width: 350)
    .padding()
}
