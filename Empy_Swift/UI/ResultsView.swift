//
//  ResultsView.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Results screen placeholder (T09)
//

import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    let transcript: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Session Complete")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Your transcript is ready")
                .foregroundColor(.secondary)
            
            // Transcript display
            ScrollView {
                Text(transcript)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }
            .frame(maxHeight: 300)
            
            // Stats
            HStack(spacing: 40) {
                VStack {
                    Text("\(transcript.split(separator: " ").count)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Words")
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(transcript.count)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Characters")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Spacer()
            
            // Actions
            HStack(spacing: 20) {
                Button("Share") {
                    // TODO: T10+ share functionality
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("New Session") {
                    coordinator.startNewSession()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .navigationTitle("Results")
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        ResultsView(transcript: "This is a sample transcript with multiple words to display in the results view.")
            .environmentObject(NavigationCoordinator())
    }
}
