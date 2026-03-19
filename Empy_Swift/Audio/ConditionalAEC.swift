//
//  ConditionalAEC.swift
//  Empy_Swift
//
//  Conditional Echo Cancellation:
//  - Enable AEC when system audio capture is OFF (mic-only mode)
//  - Disable AEC when system audio capture is ON (prevent mic suppression)
//

import Foundation
import AVFoundation

/// Manages conditional echo cancellation on AVAudioEngine.inputNode
/// 
/// **Problem without this:**
/// - macOS AEC (voiceProcessingEnabled) is too aggressive
/// - When system audio plays through speakers, AEC treats it as echo
/// - Microphone signal gets fully suppressed (0% user voice transcription)
///
/// **Solution:**
/// - Only enable AEC in mic-only mode (no system audio capture)
/// - Disable AEC when capturing system audio (avoid false positive suppression)
///
/// **Trade-off:**
/// - Without headphones + system capture ON: user voice may leak into system stream
/// - But better than silencing microphone completely
class ConditionalAEC {
    
    private let engine: AVAudioEngine
    private let logger: SessionLogger
    
    /// Current AEC state
    private(set) var isEnabled: Bool = false
    
    init(engine: AVAudioEngine, logger: SessionLogger = .shared) {
        self.engine = engine
        self.logger = logger
    }
    
    /// Enable or disable AEC based on system audio capture state
    /// - Parameter systemAudioActive: true if system audio is being captured
    func update(systemAudioActive: Bool) {
        let shouldEnable = !systemAudioActive
        
        guard shouldEnable != isEnabled else {
            return  // No change needed
        }
        
        do {
            try setAEC(enabled: shouldEnable)
            isEnabled = shouldEnable
            
            logger.log(
                event: "aec_state_changed",
                layer: "audio",
                details: [
                    "enabled": String(shouldEnable),
                    "reason": systemAudioActive ? "system_audio_active" : "mic_only"
                ]
            )
        } catch {
            logger.log(
                event: "aec_toggle_failed",
                layer: "audio",
                details: ["error": error.localizedDescription]
            )
        }
    }
    
    private func setAEC(enabled: Bool) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw NSError(
                domain: "ConditionalAEC",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No audio unit available"]
            )
        }
        
        var enabledValue: UInt32 = enabled ? 1 : 0
        let status = AudioUnitSetProperty(
            audioUnit,
            kAUVoiceIOProperty_VoiceProcessingEnable,
            kAudioUnitScope_Global,
            0,
            &enabledValue,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        guard status == noErr else {
            throw NSError(
                domain: "ConditionalAEC",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "AudioUnit property set failed"]
            )
        }
    }
}
