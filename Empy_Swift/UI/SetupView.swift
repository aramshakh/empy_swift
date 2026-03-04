//
//  SetupView.swift
//  Empy_Swift
//
//  T10: Meeting setup view with empy-trone design
//  Reference: empyai/empy-trone ConversationCreatePage
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
            return "Pitch for VC, investors, angels."
        case .jobInterview:
            return "General interview like screening, skills assessment."
        case .coaching:
            return "Private session."
        case .clientBriefing:
            return "Client briefing or qualification."
        case .clientSync:
            return "Product demo, requirements gathering."
        }
    }
}

// MARK: - Setup View
struct SetupView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    @State private var selectedCallType: CallType = .fundraising
    @State private var participantContext: String = ""
    
    private let maxChars = 8000
    
    var body: some View {
        ZStack {
            // Gradient background
            (colorScheme == .dark ? Color.empyGradientDark : Color.empyGradientLight)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: EmpySpacing.xl) {
                    // Header
                    Text("Create new conversation")
                        .font(.empyTitle)
                        .foregroundColor(colorScheme == .dark ? .empyForegroundDark : .empyForegroundLight)
                        .padding(.top, EmpySpacing.md)
                    
                    // Main card
                    EmpyCard {
                        VStack(alignment: .leading, spacing: EmpySpacing.xl) {
                            // Call type selector
                            callTypeSection
                            
                            // Participant context
                            participantContextSection
                            
                            // How it works
                            howItWorksSection
                            
                            // Submit button
                            EmpyButton(title: "Create conversation") {
                                coordinator.startRecording()
                            }
                        }
                    }
                }
                .padding(.horizontal, EmpyLayout.pagePadding)
                .padding(.bottom, EmpySpacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Setup")
    }
    
    // MARK: - Call Type Section
    
    private var callTypeSection: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.xs) {
            HStack(spacing: 4) {
                Text("Call type")
                    .font(.empyLabel)
                    .foregroundColor(colorScheme == .dark ? .empyForegroundDark : .empyForegroundLight)
                
                Text("*")
                    .font(.empyLabel)
                    .foregroundColor(.red)
            }
            
            Text("Choose the scenario you're preparing for.")
                .font(.empyCaption)
                .foregroundColor(.empySecondaryText)
            
            // Custom picker styled as menu
            Menu {
                ForEach(CallType.allCases) { type in
                    Button {
                        selectedCallType = type
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue)
                                .font(.empyLabelRegular)
                            Text(type.description)
                                .font(.empyCaption)
                                .foregroundColor(.empySecondaryText)
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedCallType.rawValue)
                            .font(.empyLabel)
                            .foregroundColor(colorScheme == .dark ? .empyForegroundDark : .empyForegroundLight)
                        
                        Text(selectedCallType.description)
                            .font(.empyCaption)
                            .foregroundColor(.empySecondaryText)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.empySecondaryText)
                }
                .padding(EmpySpacing.sm)
                .background(colorScheme == .dark ? Color.empyBackgroundDark : Color.white)
                .cornerRadius(EmpyRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: EmpyRadius.md)
                        .stroke(colorScheme == .dark ? Color.empyBorderDark : Color.empyBorderLight, lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Participant Context Section
    
    private var participantContextSection: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.xs) {
            Text("Participant context")
                .font(.empyLabel)
                .foregroundColor(colorScheme == .dark ? .empyForegroundDark : .empyForegroundLight)
            
            Text("Share key details about the other side so Empy can tailor guidance.")
                .font(.empyCaption)
                .foregroundColor(.empySecondaryText)
            
            // TextEditor styled
            ZStack(alignment: .topLeading) {
                if participantContext.isEmpty {
                    Text("Jane Doe, Partner at Moonlight Ventures (Series A focus). Already saw the deck, interested in AI vertical SaaS.")
                        .font(.empyBodyMedium)
                        .foregroundColor(.empySecondaryText.opacity(0.5))
                        .padding(EmpySpacing.xs)
                }
                
                TextEditor(text: $participantContext)
                    .font(.empyBodyMedium)
                    .foregroundColor(colorScheme == .dark ? .empyForegroundDark : .empyForegroundLight)
                    .frame(minHeight: 120)
                    .padding(4)
                    .background(colorScheme == .dark ? Color.empyBackgroundDark : Color.white)
                    .cornerRadius(EmpyRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: EmpyRadius.md)
                            .stroke(colorScheme == .dark ? Color.empyBorderDark : Color.empyBorderLight, lineWidth: 1)
                    )
                    .onChange(of: participantContext) { newValue in
                        if newValue.count > maxChars {
                            participantContext = String(newValue.prefix(maxChars))
                        }
                    }
            }
            
            HStack {
                Spacer()
                Text("\(participantContext.count)/\(maxChars)")
                    .font(.empyCaption)
                    .foregroundColor(.empySecondaryText)
            }
        }
    }
    
    // MARK: - How It Works Section
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.sm) {
            Text("HOW IT WORKS")
                .font(.empyCaptionSemibold)
                .foregroundColor(.empySecondaryText)
                .tracking(1)
            
            howItWorksStep(number: "1", text: "Join your video call (Google Meet, Zoom, MS Teams, or any).")
            howItWorksStep(number: "2", text: "Click Create conversation.")
            howItWorksStep(number: "3", text: "Keep Empy running and speak normally.")
            howItWorksStep(number: "4", text: "When you're done, click End to generate the call report.")
        }
        .padding(EmpySpacing.md)
        .background((colorScheme == .dark ? Color.empySecondaryLight.opacity(0.05) : Color.empySecondaryLight))
        .cornerRadius(EmpyRadius.lg)
    }
    
    @ViewBuilder
    private func howItWorksStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: EmpySpacing.sm) {
            Text(number)
                .font(.empyCaptionSemibold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.empyAccent)
                .clipShape(Circle())
            
            Text(text)
                .font(.empyLabelRegular)
                .foregroundColor(colorScheme == .dark ? .empyForegroundDark : .empyForegroundLight)
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
