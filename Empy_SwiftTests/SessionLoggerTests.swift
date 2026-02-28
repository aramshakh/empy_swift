//
//  SessionLoggerTests.swift
//  Empy_SwiftTests
//
//  Created by Swift Coder Agent on 2026-02-28.
//  Task: T04 - Structured Logger Tests
//

import XCTest
@testable import Empy_Swift

final class SessionLoggerTests: XCTestCase {
    
    func testLoggerCreatesFile() throws {
        let logger = SessionLogger.shared
        let sessionId = UUID().uuidString
        
        logger.startSession(id: sessionId)
        
        // Wait for session to start
        Thread.sleep(forTimeInterval: 0.1)
        
        for i in 0..<100 {
            let event = LogEvent(
                sessionId: sessionId,
                event: "test_event",
                layer: "test",
                tMonotonic: Int64(i)
            )
            logger.log(event)
        }
        
        // Wait for all logs to be written
        Thread.sleep(forTimeInterval: 0.5)
        
        logger.endSession()
        
        // Wait for session to end
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify file exists and has 100 lines
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/EmpyTrone/\(sessionId).jsonl")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath.path))
        
        let content = try String(contentsOf: logPath)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 100)
        
        // Verify each line is valid JSON and can be decoded
        for line in lines {
            let data = line.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(LogEvent.self, from: data)
            XCTAssertEqual(decoded.sessionId, sessionId)
            XCTAssertEqual(decoded.event, "test_event")
            XCTAssertEqual(decoded.layer, "test")
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: logPath)
    }
    
    func testThreadSafety() throws {
        let logger = SessionLogger.shared
        let sessionId = UUID().uuidString
        
        logger.startSession(id: sessionId)
        
        // Wait for session to start
        Thread.sleep(forTimeInterval: 0.1)
        
        let expectation = XCTestExpectation(description: "Concurrent logging")
        expectation.expectedFulfillmentCount = 100
        
        // Log 100 times concurrently
        for i in 0..<100 {
            DispatchQueue.global().async {
                let event = LogEvent(
                    sessionId: sessionId,
                    event: "concurrent_test",
                    layer: "test",
                    tMonotonic: Int64(i)
                )
                logger.log(event)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Wait for all logs to be written
        Thread.sleep(forTimeInterval: 0.5)
        
        logger.endSession()
        
        // Wait for session to end
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify file has exactly 100 lines
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/EmpyTrone/\(sessionId).jsonl")
        
        let content = try String(contentsOf: logPath)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 100)
        
        // Cleanup
        try? FileManager.default.removeItem(at: logPath)
    }
}
