//
//  SessionTimerView.swift
//  Empy_Swift
//
//  T13: Session timer component
//

import SwiftUI

struct SessionTimerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    
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
    }
    
    private var formattedTime: String {
        let totalSeconds = Int(sessionManager.elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    SessionTimerView()
        .frame(width: 280)
        .padding()
}
