//
//  ConversationManager.swift
//  Empy_Swift
//
//  Manages the Empy backend conversation lifecycle and processing loop.
//  Batches transcripts every 40s, sends to /process, publishes nudges + stats.
//

import Foundation
import Combine

class ConversationManager: ObservableObject {
    
    // MARK: - Published State (for UI)
    
    @Published private(set) var coachCards: [CoachCard] = []
    @Published private(set) var speakingRatioMe: Double = 0.5
    @Published private(set) var latestStatistics: ConversationStatistics?
    @Published private(set) var summary: ConversationSummary?
    @Published private(set) var reportId: String?
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastError: String?
    
    // MARK: - Internal State
    
    private(set) var conversationId: String?
    
    // Dependencies
    private let apiClient: EmpyAPIClient
    private let logger: SessionLogger
    
    // Processing loop
    private var processingTimer: AnyCancellable?
    private let processingInterval: TimeInterval = 40.0
    private let flushThreshold: Int = 4
    
    // Batch accumulation (protected by queue)
    private let queue = DispatchQueue(label: "com.empytrone.conversationmanager", qos: .userInitiated)
    private var pendingSegments: [ConversationEntry] = []
    private var nextSegmentId: Int = 0
    
    // Deduplication
    private var sentEntryFingerprints: Set<String> = []
    private var seenNudgeIds: Set<String> = []
    
    // MARK: - Init
    
    init(
        apiClient: EmpyAPIClient = EmpyAPIClient(),
        logger: SessionLogger = .shared
    ) {
        self.apiClient = apiClient
        self.logger = logger
    }
    
    // MARK: - Conversation Lifecycle
    
    /// Start a new conversation with the backend
    func startConversation(
        callType: String,
        participantContext: String,
        goal: String = "",
        duration: Int = 30
    ) {
        guard FeatureFlags.empyAPIEnabled else { return }
        
        // Reset state
        queue.sync {
            pendingSegments.removeAll()
            sentEntryFingerprints.removeAll()
            seenNudgeIds.removeAll()
            nextSegmentId = 0
        }
        
        DispatchQueue.main.async {
            self.coachCards.removeAll()
            self.summary = nil
            self.reportId = nil
            self.latestStatistics = nil
            self.speakingRatioMe = 0.5
            self.lastError = nil
        }
        
        let request = CreateConversationRequest(
            userId: AppConfig.userId,
            agenda: callType,
            meetingInfo: MeetingInfo(
                goal: goal.isEmpty ? callType : goal,
                duration: duration,
                participantContext: participantContext
            )
        )
        
        Task {
            do {
                let response = try await apiClient.createConversation(request)
                self.conversationId = response.conversationId
                
                logger.log(
                    event: "conversation_created",
                    layer: "api",
                    details: ["conversation_id": response.conversationId]
                )
                
                startProcessingLoop()
                
            } catch {
                logger.log(
                    event: "conversation_create_failed",
                    layer: "api",
                    details: ["error": error.localizedDescription]
                )
                await MainActor.run {
                    self.lastError = "Failed to create conversation: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// End the conversation and get summary
    func endConversation() {
        guard FeatureFlags.empyAPIEnabled else { return }
        guard let convId = conversationId else { return }
        
        processingTimer?.cancel()
        processingTimer = nil
        
        Task {
            // Process final batch
            await processPendingBatch()
            
            do {
                let response = try await apiClient.endConversation(id: convId)
                
                logger.log(
                    event: "conversation_ended",
                    layer: "api",
                    details: [
                        "conversation_id": convId,
                        "report_id": response.reportId
                    ]
                )
                
                await MainActor.run {
                    self.summary = response.summary
                    self.reportId = response.reportId
                }
                
            } catch {
                logger.log(
                    event: "conversation_end_failed",
                    layer: "api",
                    details: ["error": error.localizedDescription]
                )
                await MainActor.run {
                    self.lastError = "Failed to end conversation: \(error.localizedDescription)"
                }
            }
            
            conversationId = nil
        }
    }
    
    // MARK: - Transcript Ingestion
    
    /// Add a final transcript segment for batch processing
    func addSegment(text: String, speaker: String, startTime: Double, endTime: Double) {
        guard conversationId != nil else { return }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let id = self.nextSegmentId
            self.nextSegmentId += 1
            
            let entry = ConversationEntry(
                id: id,
                text: text,
                timeStart: startTime,
                timeEnd: endTime,
                speaker: speaker,
                type: nil
            )
            
            self.pendingSegments.append(entry)
            
            if self.pendingSegments.count >= self.flushThreshold {
                Task { await self.processPendingBatch() }
            }
        }
    }
    
    // MARK: - Card Management
    
    func dismissCard(_ card: CoachCard) {
        coachCards.removeAll { $0.id == card.id }
    }
    
    /// Fetch coaching advice for a specific coach card
    func fetchAdvice(for card: CoachCard) async -> String? {
        guard let nudgeId = card.nudgeId,
              let convId = card.conversationId else { return nil }
        
        let nudgeDTO = NudgeDTO(
            conversationId: convId,
            text: card.message,
            nudgeId: nudgeId,
            timestamp: card.timestamp.timeIntervalSince1970,
            type: card.type == .warning ? "risk_check" : "engagement_check",
            severity: card.type == .warning ? "negative" : (card.type == .insight ? "positive" : "neutral")
        )
        
        do {
            let response = try await apiClient.getAdvice(AdviceRequest(nudge: nudgeDTO))
            return response.text
        } catch {
            logger.log(
                event: "advice_fetch_failed",
                layer: "api",
                details: ["error": error.localizedDescription]
            )
            return nil
        }
    }
    
    // MARK: - Private
    
    private func startProcessingLoop() {
        processingTimer?.cancel()
        processingTimer = Timer.publish(every: processingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { await self.processPendingBatch() }
            }
    }
    
    private func processPendingBatch() async {
        guard let convId = conversationId else { return }
        
        let batch: [ConversationEntry] = queue.sync {
            guard !pendingSegments.isEmpty else { return [] }
            
            var deduped: [ConversationEntry] = []
            for entry in pendingSegments {
                let fingerprint = "\(entry.speaker):\(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                if !sentEntryFingerprints.contains(fingerprint) {
                    sentEntryFingerprints.insert(fingerprint)
                    deduped.append(entry)
                }
            }
            
            pendingSegments.removeAll()
            return deduped
        }
        
        guard !batch.isEmpty else { return }
        
        await MainActor.run { self.isProcessing = true }
        
        let request = ProcessRequest(
            id: convId,
            conversation: batch,
            debug: false
        )
        
        do {
            let response = try await apiClient.processTranscripts(request)
            
            logger.log(
                event: "process_response",
                layer: "api",
                details: [
                    "nudges": "\(response.nudges.count)",
                    "batch_size": "\(batch.count)"
                ]
            )
            
            await MainActor.run {
                self.isProcessing = false
                
                // Handle nudges -> coach cards
                for nudge in response.nudges {
                    guard !self.seenNudgeIds.contains(nudge.nudgeId) else { continue }
                    self.seenNudgeIds.insert(nudge.nudgeId)
                    self.coachCards.append(nudge.toCoachCard())
                }
                
                // Handle statistics
                if let stats = response.statistics {
                    self.latestStatistics = stats
                    if let me = stats.speakingRatio?.speakers["me"] {
                        self.speakingRatioMe = me / 100.0
                    }
                }
            }
            
        } catch {
            logger.log(
                event: "process_failed",
                layer: "api",
                details: ["error": error.localizedDescription]
            )
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }
}
