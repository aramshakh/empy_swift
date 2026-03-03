//
//  SetupView.swift
//  Empy_Swift
//
//  T10: Meeting setup view (real form)
//  Reference: empy-trone ConversationCreatePage
//

import SwiftUI

// MARK: - Call Type Model
enum CallType: String, CaseIterable, Identifiable {
    case fundraising = "Fundraising"
    case jobInterview = "Job interview"
    case coaching = "1:1 coaching session"
    case clientBriefing = "Client briefing"
    case clientSync = "Client sync"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .fundraising:
            return "Pitch for VC, investors, angels"
        case .jobInterview:
            return "General interview like screening, skills assessment"
        case .coaching:
            return "Private session"
        case .clientBriefing:
            return "Client briefing or qualification"
        case .clientSync:
            return "Product demo, requirements gathering"
        }
    }
}

// MARK: - Setup View
struct SetupView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    @State private var selectedCallType: CallType = .fundraising
    @State private var participantContext: String = ""
    
    private let maxChars = 8000
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Create new conversation")
                    .font(.title)
                    .fontWeight(.semibold)
                
                // Call type selector
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Call type")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("*")
                            .foregroundColor(.red)
                    }
                    
                    Text("Choose the scenario you're preparing for.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Call type", selection: $selectedCallType) {
                        ForEach(CallType.allCases) { type in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(type.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Participant context field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Participant context")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Share key details about the other side so Empy can tailor guidance.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $participantContext)
                        .frame(minHeight: 120)
                        .font(.body)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .onChange(of: participantContext) { newValue in
                            if newValue.count > maxChars {
                                participantContext = String(newValue.prefix(maxChars))
                            }
                        }
                    
                    HStack {
                        Spacer()
                        Text("\(participantContext.count)/\(maxChars)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // "How it works" section
                VStack(alignment: .leading, spacing: 12) {
                    Text("HOW IT WORKS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .tracking(1)
                    
                    howItWorksStep(
                        number: "1",
                        text: "Join your video call (Google Meet, Zoom, MS Teams, or any)."
                    )
                    
                    howItWorksStep(
                        number: "2",
                        text: "Click Create conversation."
                    )
                    
                    howItWorksStep(
                        number: "3",
                        text: "Keep Empy running and speak normally."
                    )
                    
                    howItWorksStep(
                        number: "4",
                        text: "When you're done, click End to generate the call report."
                    )
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Submit button
                Button(action: {
                    // TODO: Pass call type and participant context to coordinator
                    coordinator.startRecording()
                }) {
                    Text("Create conversation")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
            }
            .padding()
        }
        .navigationTitle("Setup")
    }
    
    // MARK: - Helper Views
    @ViewBuilder
    private func howItWorksStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        SetupView()
            .environmentObject(NavigationCoordinator())
    }
}
