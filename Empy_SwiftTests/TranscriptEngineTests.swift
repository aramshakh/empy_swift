//
//  TranscriptEngineTests.swift
//  Empy_SwiftTests
//
//  Created by Orchestrator on 2026-03-03.
//  Tests for TranscriptEngine transcript accumulation
//

import XCTest
@testable import Empy_Swift

class TranscriptEngineTests: XCTestCase {
    var engine: TranscriptEngine!
    var mockClient: MockDeepgramClient!
    var mockLogger: MockSessionLogger!
    
    override func setUp() {
        super.setUp()
        
        // Set test API key
        setenv("EMPY_DEEPGRAM_KEY", "test_key_12345", 1)
        
        mockLogger = MockSessionLogger()
        mockClient = MockDeepgramClient(logger: mockLogger)
        engine = TranscriptEngine(deepgramClient: mockClient, logger: mockLogger)
    }
    
    override func tearDown() {
        engine = nil
        mockClient = nil
        mockLogger = nil
        
        unsetenv("EMPY_DEEPGRAM_KEY")
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testPartialReplacement() {
        // Given: Two partials arrive
        engine.deepgramClient(mockClient, didReceivePartialTranscript: "Hello")
        
        // Then: One segment present
        XCTAssertEqual(engine.transcriptState.segments.count, 1)
        XCTAssertEqual(engine.transcriptState.fullText, "Hello")
        
        // When: Second partial arrives
        engine.deepgramClient(mockClient, didReceivePartialTranscript: "Hello world")
        
        // Then: Still one segment (replaced)
        XCTAssertEqual(engine.transcriptState.segments.count, 1)
        XCTAssertEqual(engine.transcriptState.fullText, "Hello world")
    }
    
    func testFinalReplacesPartial() {
        // Given: Partial arrives
        engine.deepgramClient(mockClient, didReceivePartialTranscript: "Hello...")
        XCTAssertEqual(engine.transcriptState.partialCount, 1)
        
        // When: Final arrives
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "Hello world")
        
        // Then: Partial replaced by final
        XCTAssertEqual(engine.transcriptState.segments.count, 1)
        XCTAssertEqual(engine.transcriptState.partialCount, 0)
        XCTAssertEqual(engine.transcriptState.finalCount, 1)
        XCTAssertTrue(engine.transcriptState.segments.first?.isFinal == true)
    }
    
    func testMultipleFinals() {
        // Given: Multiple finals arrive
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "Hello")
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "world")
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "!")
        
        // Then: All finals present
        XCTAssertEqual(engine.transcriptState.segments.count, 3)
        XCTAssertEqual(engine.transcriptState.finalCount, 3)
        XCTAssertEqual(engine.transcriptState.fullText, "Hello world !")
    }
    
    func testClearState() {
        // Given: Some transcripts present
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "Test 1")
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "Test 2")
        XCTAssertEqual(engine.transcriptState.segments.count, 2)
        
        // When: Clear state
        engine.clearState()
        
        // Then: State reset
        XCTAssertEqual(engine.transcriptState.segments.count, 0)
        XCTAssertEqual(engine.transcriptState.fullText, "")
        XCTAssertEqual(engine.transcriptState.wordCount, 0)
    }
    
    func testFullTextGeneration() {
        // Given: Multiple segments
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "Hello")
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "world")
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "how are you")
        
        // Then: Full text joined correctly
        XCTAssertEqual(engine.transcriptState.fullText, "Hello world how are you")
    }
    
    func testWordCount() {
        // Given: Segments with multiple words
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "Hello world")
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "How are you")
        
        // Then: Word count correct
        XCTAssertEqual(engine.transcriptState.wordCount, 5) // 2 + 3
    }
    
    func testSessionLifecycle() {
        // When: Start session
        engine.startSession()
        
        // Then: Should log event
        let startLogs = mockLogger.loggedEvents.filter { $0.event == "transcription_session_started" }
        XCTAssertGreaterThan(startLogs.count, 0)
        
        // When: End session
        engine.endSession()
        
        // Then: Should log event
        let endLogs = mockLogger.loggedEvents.filter { $0.event == "transcription_session_ended" }
        XCTAssertGreaterThan(endLogs.count, 0)
    }
    
    func testEmptyFinalIgnored() {
        // Given: Empty final arrives
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "")
        
        // Then: No segment added
        XCTAssertEqual(engine.transcriptState.segments.count, 0)
    }
    
    func testPartialAfterFinalIgnored() {
        // Given: Final arrives
        engine.deepgramClient(mockClient, didReceiveFinalTranscript: "Hello world")
        XCTAssertEqual(engine.transcriptState.finalCount, 1)
        
        // When: Partial arrives immediately after
        engine.deepgramClient(mockClient, didReceivePartialTranscript: "Stale partial")
        
        // Then: Partial ignored (out-of-order protection)
        XCTAssertEqual(engine.transcriptState.segments.count, 1) // Still just 1 final
        XCTAssertEqual(engine.transcriptState.partialCount, 0)
    }
}

// MARK: - Mock DeepgramClient

class MockDeepgramClient: DeepgramClient {
    override func connect() throws {
        // Mock: do nothing
    }
    
    override func disconnect() {
        // Mock: do nothing
    }
    
    override func send(audioData: Data) {
        // Mock: do nothing
    }
}
