//
//  SetupView.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Setup screen placeholder (T09)
//

import SwiftUI

struct SetupView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Empy Setup")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Configure your recording settings")
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Start Recording") {
                coordinator.startRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Setup")
    }
}

#Preview {
    NavigationStack {
        SetupView()
            .environmentObject(NavigationCoordinator())
    }
}
