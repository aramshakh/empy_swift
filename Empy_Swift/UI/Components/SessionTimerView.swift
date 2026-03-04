//
//  SessionTimerView.swift
//  Empy_Swift
//
//  T13: Session timer component
//

import SwiftUI
import Combine

struct SessionTimerView: View {
    let startTime: Date
    
    @State private var elapsedTime: TimeInterval = 0
    @State private var timerSubscription: AnyCancellable?
    
    var body: some View {
        Text(formattedTime)
            .font(.system(.title2, design: .monospaced))
            .foregroundColor(.primary)
            .onAppear {
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
    }
    
    private var formattedTime: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        
        // If < 1 hour: MM:SS, else H:MM:SS
        if elapsedTime < 3600 {
            formatter.allowedUnits = [.minute, .second]
        } else {
            formatter.allowedUnits = [.hour, .minute, .second]
        }
        
        return formatter.string(from: elapsedTime) ?? "00:00"
    }
    
    private func startTimer() {
        // Update immediately
        elapsedTime = Date.now.timeIntervalSince(startTime)
        
        // Update every second
        timerSubscription = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                elapsedTime = Date.now.timeIntervalSince(startTime)
            }
    }
    
    private func stopTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
    }
}

// Preview
struct SessionTimerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Started 5 minutes ago
            SessionTimerView(startTime: Date.now.addingTimeInterval(-300))
                .previewDisplayName("5 minutes")
            
            // Started 1 hour 23 minutes ago
            SessionTimerView(startTime: Date.now.addingTimeInterval(-4980))
                .previewDisplayName("1:23:00")
        }
        .padding()
    }
}
