//
//  AECProcessor.swift
//  Empy_Swift
//
//  Neural acoustic echo cancellation via DTLN-aec CoreML.
//  Wraps DTLNAecEchoProcessor so AudioEngine can call it without
//  knowing the CoreML details.
//
//  Integration points:
//    1. AudioEngine feeds mic buffers through processNearEnd(_:)
//    2. DualStreamManager feeds system audio through feedFarEnd(_:)
//
//  IMPORTANT: This file compiles cleanly even when the DTLNAec256
//  package is not yet added — all DTLN types are hidden behind #if canImport.
//  Once you add the package in Xcode the real implementation activates.
//

import Foundation
import AVFoundation

#if canImport(DTLNAecCoreML) && canImport(DTLNAec256)
import DTLNAecCoreML
import DTLNAec256
#endif

/// Thread-safe wrapper around DTLNAecEchoProcessor.
/// All calls must come from the same serial queue (AudioEngine's tap queue).
final class AECProcessor {

    // MARK: - State

    private var isLoaded = false

    #if canImport(DTLNAecCoreML) && canImport(DTLNAec256)
    private var processor: DTLNAecEchoProcessor?
    #endif

    // MARK: - Init

    init() {}

    // MARK: - Lifecycle

    /// Load CoreML models asynchronously. Call once before the session starts.
    func loadIfNeeded() async {
        guard !isLoaded else { return }
        #if canImport(DTLNAecCoreML) && canImport(DTLNAec256)
        do {
            let p = DTLNAecEchoProcessor(modelSize: .medium)
            try await p.loadModelsAsync(from: DTLNAec256.bundle)
            processor = p
            isLoaded = true
            print("✅ AEC models loaded (DTLN-256)")
        } catch {
            print("⚠️ AEC model load failed: \(error) — running without echo cancellation")
        }
        #else
        print("⚠️ DTLNAec256 package not found — running without echo cancellation")
        #endif
    }

    /// Reset LSTM state between sessions.
    func reset() {
        #if canImport(DTLNAecCoreML) && canImport(DTLNAec256)
        processor?.resetStates()
        #endif
    }

    // MARK: - Processing

    /// Feed system audio (far-end / loudspeaker signal) into the echo estimator.
    /// Call this for every system audio buffer from ScreenCaptureKit,
    /// before or at the same time as processNearEnd.
    func feedFarEnd(_ samples: [Float]) {
        #if canImport(DTLNAecCoreML) && canImport(DTLNAec256)
        processor?.feedFarEnd(samples)
        #endif
    }

    /// Process microphone audio (near-end) and return echo-cancelled samples.
    /// Returns the original samples unchanged if AEC is not loaded.
    func processNearEnd(_ samples: [Float]) -> [Float] {
        #if canImport(DTLNAecCoreML) && canImport(DTLNAec256)
        if let p = processor {
            return p.processNearEnd(samples)
        }
        #endif
        return samples
    }

    /// Flush any buffered output at end of session.
    func flush() -> [Float] {
        #if canImport(DTLNAecCoreML) && canImport(DTLNAec256)
        return processor?.flush() ?? []
        #else
        return []
        #endif
    }

    var available: Bool { isLoaded }
}
