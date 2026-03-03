//
//  SessionTimerView.swift
//  Empy_Swift
//
//  T13: Session timer component
//

import SwiftUI

struct SessionTimerView: View {
    @State private var elapsedSeconds: Int = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: EmpySpacing.xs) {
            Text("Session Time")
                .font(.empyCaption)
                .foregroundColor(.empySecondaryText)
            
            Text(formattedTime)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .padding(EmpySpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: EmpyRadius.md)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .onReceive(timer) { _ in
            elapsedSeconds += 1
        }
    }
    
    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    SessionTimerView()
        .frame(width: 280)
        .padding()
}
