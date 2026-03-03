//
//  DeepgramClientTests.swift
//  Empy_SwiftTests
//
//  Created by Orchestrator on 2026-03-03.
//  Tests for DeepgramClient WebSocket functionality
//

import XCTest
@testable import Empy_Swift

class DeepgramClientTests: XCTestCase {
    var client: DeepgramClient!
    var mockDelegate: MockDeepgramDelegate!
    var mockLogger: MockSessionLogger!
    
    override func setUp() {
        super.setUp()
        
        // Set test API key via environment
        setenv("EMPY_DEEPGRAM_KEY", "test_api_key_12345", 1)
        
        mockLogger = MockSessionLogger()
        mockDelegate = MockDeepgramDelegate()
        
        client = DeepgramClient(logger: mockLogger)
        client.delegate = mockDelegate
    }
    
    override func tearDown() {
        client.disconnect()
        client = nil
        mockDelegate = nil
        mockLogger = nil
        
        // Clean up environment
        unsetenv("EMPY_DEEPGRAM_KEY")
        
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testConnectionRequiresAPIKey() {
        // Given: No API key (unset environment)
        unsetenv("EMPY_DEEPGRAM_KEY")
        
        // When/Then: Should throw error
        XCTAssertThrowsError(try client.connect()) { error in
            XCTAssertEqual(error as? DeepgramClientError, .missingAPIKey)
        }
        
        // Restore for other tests
        setenv("EMPY_DEEPGRAM_KEY", "test_api_key_12345", 1)
    }
    
    func testConnectionLogsEvent() throws {
        // When
        try client.connect()
        
        // Then
        let connectLogs = mockLogger.loggedEvents.filter { $0.event == "deepgram_connecting" }
        XCTAssertGreaterThan(connectLogs.count, 0, "Should log connection attempt")
        
        // Cleanup
        client.disconnect()
    }
    
    func testDisconnectClearsState() throws {
        // Given: Connected client
        try client.connect()
        
        // When
        client.disconnect()
        
        // Then
        XCTAssertFalse(client.isConnected)
        let disconnectLogs = mockLogger.loggedEvents.filter { $0.event == "deepgram_disconnected" }
        XCTAssertGreaterThan(disconnectLogs.count, 0)
    }
    
    func testSendAudioWhenDisconnectedBuffers() {
        // Given: Disconnected client
        let audioData = Data(repeating: 0, count: 1000)
        
        // When
        client.send(audioData: audioData)
        
        // Then: Should log buffering
        let bufferLogs = mockLogger.loggedEvents.filter { $0.event == "deepgram_audio_buffered" }
        XCTAssertGreaterThan(bufferLogs.count, 0, "Should buffer audio when disconnected")
    }
    
    func testReconnectionStrategyExponentialBackoff() {
        var strategy = ReconnectionStrategy()
        
        // Test exponential backoff sequence
        XCTAssertEqual(strategy.nextDelay(), 1.0) // 2^0 = 1s
        XCTAssertEqual(strategy.nextDelay(), 2.0) // 2^1 = 2s
        XCTAssertEqual(strategy.nextDelay(), 4.0) // 2^2 = 4s
        XCTAssertEqual(strategy.nextDelay(), 8.0) // 2^3 = 8s
        XCTAssertEqual(strategy.nextDelay(), 16.0) // 2^4 = 16s
        XCTAssertNil(strategy.nextDelay()) // Max attempts reached
        
        // Test reset
        strategy.reset()
        XCTAssertEqual(strategy.nextDelay(), 1.0) // Back to 1s
    }
    
    func testDeepgramMessageParsingTranscript() {
        let json = """
        {
            "type": "Results",
            "channel": {
                "alternatives": [
                    {
                        "transcript": "Hello world",
                        "confidence": 0.95
                    }
                ]
            },
            "isFinal": true
        }
        """
        
        let response = DeepgramResponse(from: json)
        
        switch response {
        case .transcript(let result):
            XCTAssertEqual(result.channel?.alternatives.first?.transcript, "Hello world")
            XCTAssertEqual(result.isFinal, true)
        default:
            XCTFail("Should parse as transcript")
        }
    }
    
    func testDeepgramMessageParsingMetadata() {
        let json = """
        {
            "type": "Metadata",
            "request_id": "req_123"
        }
        """
        
        let response = DeepgramResponse(from: json)
        
        switch response {
        case .metadata(let metadata):
            XCTAssertEqual(metadata.type, "Metadata")
            XCTAssertEqual(metadata.requestId, "req_123")
        default:
            XCTFail("Should parse as metadata")
        }
    }
    
    func testDeepgramMessageParsingError() {
        let json = """
        {
            "type": "Error",
            "message": "Invalid audio format"
        }
        """
        
        let response = DeepgramResponse(from: json)
        
        switch response {
        case .error(let error):
            XCTAssertEqual(error.message, "Invalid audio format")
        default:
            XCTFail("Should parse as error")
        }
    }
    
    func testDelegateMethodsAreDefined() {
        // This test ensures delegate protocol is implemented
        // Mock delegate should not crash when methods are called
        
        mockDelegate.onPartialTranscript = { transcript in
            XCTAssertNotNil(transcript)
        }
        
        client.delegate?.deepgramClient(client, didReceivePartialTranscript: "test")
        XCTAssertTrue(mockDelegate.partialTranscriptCalled)
    }
}

// MARK: - Mock Delegate

class MockDeepgramDelegate: DeepgramClientDelegate {
    var connectCalled = false
    var disconnectCalled = false
    var partialTranscriptCalled = false
    var finalTranscriptCalled = false
    var errorCalled = false
    
    var onPartialTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript transcript: String) {
        partialTranscriptCalled = true
        onPartialTranscript?(transcript)
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String) {
        finalTranscriptCalled = true
        onFinalTranscript?(transcript)
    }
    
    func deepgramClient(_ client: DeepgramClient, didEncounterError error: Error) {
        errorCalled = true
        onError?(error)
    }
    
    func deepgramClientDidConnect(_ client: DeepgramClient) {
        connectCalled = true
    }
    
    func deepgramClientDidDisconnect(_ client: DeepgramClient) {
        disconnectCalled = true
    }
}


