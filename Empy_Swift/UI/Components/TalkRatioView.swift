//
//  TalkRatioView.swift
//  Empy_Swift
//
//  Talk ratio indicator component showing user vs participant speaking time
//

import SwiftUI

struct TalkRatioView: View {
    let userPercentage: Double // 0.0 to 1.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.sm) {
            // Header
            HStack {
                Text("Talk Ratio")
                    .font(.empyLabel)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(userPercentage * 100))% you")
                    .font(.empyCaption)
                    .foregroundColor(.secondary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background (participant)
                    RoundedRectangle(cornerRadius: EmpyRadius.sm)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // Foreground (user)
                    RoundedRectangle(cornerRadius: EmpyRadius.sm)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * userPercentage, height: 8)
                }
            }
            .frame(height: 8)
            
            // Legend
            HStack(spacing: EmpySpacing.md) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("You")
                        .font(.empyCaption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 8, height: 8)
                    Text("Participant")
                        .font(.empyCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(EmpySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: EmpyRadius.md)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        TalkRatioView(userPercentage: 0.65)
        TalkRatioView(userPercentage: 0.30)
        TalkRatioView(userPercentage: 0.50)
    }
    .frame(width: 280)
    .padding()
}
