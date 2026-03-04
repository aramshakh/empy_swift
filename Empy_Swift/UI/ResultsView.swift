//
//  ResultsView.swift
//  Empy_Swift
//
//  Results screen with real summary, takeaways, and agenda coverage (T09)
//

import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @EnvironmentObject var conversationManager: ConversationManager
    let transcript: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EmpySpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: EmpySpacing.xs) {
                    Text("Session Complete")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Your session has been analyzed")
                        .foregroundColor(.empySecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Summary section — spinner until data arrives
                if conversationManager.isProcessing {
                    summaryLoadingView()
                } else if let summary = conversationManager.summary {
                    summarySection(summary)
                } else {
                    // API disabled or no summary returned — show transcript
                    transcriptSection()
                }
                
                // Speaking ratio
                speakingRatioSection(conversationManager.speakingRatioMe)
                
                Spacer()
                
                // Actions
                HStack(spacing: EmpySpacing.md) {
                    Button("Share") {
                        // TODO: share functionality
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button("New Session") {
                        coordinator.startNewSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(EmpySpacing.lg)
        }
        .navigationTitle("Results")
        .navigationBarBackButtonHidden(true)
    }
    
    // MARK: - Summary Loading
    
    private func summaryLoadingView() -> some View {
        HStack(spacing: EmpySpacing.sm) {
            ProgressView()
            Text("Generating summary…")
                .font(.empyBody)
                .foregroundColor(.empySecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(EmpySpacing.lg)
    }
    
    // MARK: - Summary Sections
    
    private func summarySection(_ summary: ConversationSummary) -> some View {
        VStack(alignment: .leading, spacing: EmpySpacing.lg) {
            // Takeaways
            if let takeaways = summary.takeaways, !takeaways.isEmpty {
                sectionHeader("Key Takeaways")
                VStack(alignment: .leading, spacing: EmpySpacing.sm) {
                    ForEach(takeaways, id: \.self) { item in
                        bulletRow(item)
                    }
                }
            }
            
            // Action points
            if let actions = summary.actionPoints, !actions.isEmpty {
                sectionHeader("Action Points")
                VStack(alignment: .leading, spacing: EmpySpacing.sm) {
                    ForEach(actions, id: \.self) { item in
                        bulletRow(item, symbol: "checkmark.circle")
                    }
                }
            }
            
            // Agenda coverage
            if let agenda = summary.agendaCoverage, !agenda.isEmpty {
                sectionHeader("Agenda Coverage")
                VStack(alignment: .leading, spacing: EmpySpacing.sm) {
                    ForEach(agenda) { item in
                        agendaRow(item)
                    }
                }
            }
            
            // Fallback: show transcript if no structured data
            if (summary.takeaways?.isEmpty ?? true) &&
               (summary.actionPoints?.isEmpty ?? true) &&
               (summary.agendaCoverage?.isEmpty ?? true) {
                transcriptSection()
            }
        }
    }
    
    // MARK: - Transcript Fallback
    
    private func transcriptSection() -> some View {
        VStack(alignment: .leading, spacing: EmpySpacing.sm) {
            sectionHeader("Transcript")
            Text(transcript.isEmpty ? "No transcript captured" : transcript)
                .font(.empyBody)
                .padding(EmpySpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            
            HStack(spacing: EmpySpacing.lg) {
                let wordCount = transcript.split(whereSeparator: \.isWhitespace).count
                statBadge(label: "Words", value: "\(wordCount)")
                statBadge(label: "Characters", value: "\(transcript.count)")
            }
        }
    }
    
    // MARK: - Speaking Ratio
    
    @ViewBuilder
    private func speakingRatioSection(_ ratio: Double) -> some View {
        if ratio > 0 {
            VStack(alignment: .leading, spacing: EmpySpacing.sm) {
                sectionHeader("Talk Ratio")
                TalkRatioView(userPercentage: ratio)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.empyTitle)
            .foregroundColor(.primary)
    }
    
    private func bulletRow(_ text: String, symbol: String = "circle.fill") -> some View {
        HStack(alignment: .top, spacing: EmpySpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 8))
                .foregroundColor(.empyAccent)
                .padding(.top, 5)
            Text(text)
                .font(.empyBody)
        }
    }
    
    private func agendaRow(_ item: AgendaCoverageItem) -> some View {
        HStack(spacing: EmpySpacing.sm) {
            Image(systemName: item.met ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(item.met ? .green : .red)
            Text(item.topic)
                .font(.empyBody)
        }
    }
    
    private func statBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.empyCaption)
                .foregroundColor(.empySecondaryText)
        }
    }
}

#Preview {
    NavigationStack {
        ResultsView(transcript: "This is a sample transcript with multiple words.")
            .environmentObject(NavigationCoordinator())
            .environmentObject(ConversationManager(apiClient: EmpyAPIClient()))
    }
}
