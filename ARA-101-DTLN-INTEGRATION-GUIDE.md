# ARA-101: DTLN-aec-coreml Integration Guide

## Status: Ready to implement

**Branch:** `feat/dtln-aec-integration`  
**Effort:** 1-2 hours  
**Impact:** Fix mic suppression without headphones

---

## Step 1: Add Swift Package (5 min)

**In Xcode:**

1. Open `Empy_Swift.xcodeproj`
2. File → Add Package Dependencies
3. Enter URL: `https://github.com/MimicScribe/dtln-aec-coreml.git`
4. Version: **0.4.0-beta** or later
5. Add to target: **Empy_Swift**

**Select products:**
- [x] DTLNAecCoreML
- [x] DTLNAec256 (recommended, 15 MB)

**Alternative (if 256 too large):**
- DTLNAec128 (7 MB, slightly worse quality)

---

## Step 2: Update DualStreamManager (1 hour)

**File:** `Empy_Swift/Audio/DualStreamManager.swift`

### 2.1 Add imports

```swift
import DTLNAecCoreML
import DTLNAec256
```

### 2.2 Add AEC processor property

```swift
class DualStreamManager: ObservableObject {
    // ... existing properties
    
    /// AEC processor for echo cancellation
    private var aecProcessor: DTLNAecEchoProcessor?
    
    /// Buffer to accumulate system audio for AEC reference
    private var systemAudioForAEC: [Float] = []
```

### 2.3 Initialize AEC in start()

```swift
func startMicOnly() throws {
    logger.log(event: "mic_stream_start", layer: "audio")
    
    // Initialize AEC processor
    if aecProcessor == nil {
        aecProcessor = DTLNAecEchoProcessor(modelSize: .medium)
        do {
            try aecProcessor?.loadModels(from: DTLNAec256.bundle)
            logger.log(event: "aec_loaded", layer: "audio")
        } catch {
            logger.log(event: "aec_load_failed", layer: "audio",
                       details: ["error": error.localizedDescription])
            // Continue without AEC (graceful degradation)
            aecProcessor = nil
        }
    }
    
    // ... rest of existing code
}
```

### 2.4 Feed system audio to AEC

**In SystemAudioCaptureDelegate:**

```swift
extension DualStreamManager: SystemAudioCaptureDelegate {
    func systemAudioDidCapture(buffer: AVAudioPCMBuffer) {
        // Convert AVAudioPCMBuffer to [Float] for AEC
        guard let floatChannelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameLength))
        
        // Feed to AEC as reference signal
        aecProcessor?.feedFarEnd(samples)
        
        // Also send to Deepgram (system audio stream)
        systemSeqId += 1
        onSystemBuffer?(buffer)
    }
}
```

### 2.5 Process mic through AEC

**In AudioEngine callback:**

```swift
func startMicOnly() throws {
    // ...
    
    audioEngine.onChunk = { [weak self] chunk in
        guard let self = self else { return }
        
        // Convert chunk PCM data to [Float] for AEC
        let floatSamples = self.pcmDataToFloatArray(chunk.pcmData)
        
        // Process through AEC if available
        var cleanSamples = floatSamples
        if let aec = self.aecProcessor {
            cleanSamples = aec.processNearEnd(floatSamples)
        }
        
        // Convert back to PCM data
        let cleanPCM = self.floatArrayToPCMData(cleanSamples)
        
        // Create clean chunk
        let cleanChunk = AudioChunk(
            seqId: chunk.seqId,
            pcmData: cleanPCM,
            timestamp: chunk.timestamp,
            source: chunk.source
        )
        
        self.onMicChunk?(cleanChunk)
    }
    
    try audioEngine.start()
}
```

### 2.6 Add conversion helpers

```swift
private func pcmDataToFloatArray(_ pcmData: Data) -> [Float] {
    // PCM Int16 → Float32 for AEC
    let int16Array = pcmData.withUnsafeBytes { ptr in
        Array(ptr.bindMemory(to: Int16.self))
    }
    return int16Array.map { Float($0) / 32768.0 }
}

private func floatArrayToPCMData(_ floats: [Float]) -> Data {
    // Float32 → PCM Int16 for Deepgram
    let int16Array = floats.map { sample in
        Int16(max(-32768, min(32767, sample * 32768.0)))
    }
    return Data(bytes: int16Array, count: int16Array.count * MemoryLayout<Int16>.size)
}
```

### 2.7 Cleanup on stop

```swift
func stop() async {
    logger.log(event: "dual_stream_stop", layer: "audio")
    
    audioEngine.stop()
    await systemAudioCapture.stop()
    
    // Flush and reset AEC
    if let aec = aecProcessor {
        _ = aec.flush()
        aec.resetStates()
    }
    
    await MainActor.run {
        self.isMicCapturing = false
        self.isSystemCapturing = false
    }
}
```

---

## Step 3: Test (30 min)

### Test Scenario 1: Mic-only (no system audio)

```
1. Start recording
2. Speak into mic (no YouTube playing)
3. Stop recording

Expected: Normal transcription, AEC bypassed
```

### Test Scenario 2: Dual-stream without headphones

```
1. Open YouTube video (play through speakers)
2. Start recording
3. Speak into mic while YouTube plays
4. Stop recording

Expected: 
- User voice transcribes correctly (You: >0%)
- YouTube transcribes separately (Participant)
- No echo in "You" transcript
```

### Test Scenario 3: Edge cases

```
1. Simultaneous speech (user + YouTube vocals)
2. Quiet room (low mic energy)
3. Loud system audio

Expected: Graceful handling, no crashes
```

---

## Step 4: Verify Improvements

**Before ARA-101 (PR #46):**
- User voice: 0% when system audio plays
- Conditional AEC: ON/OFF toggle

**After ARA-101:**
- User voice: >80% transcription rate
- AEC: Always active, uses system audio as reference
- Echo suppression: ~50dB

**Metrics to check:**
- "You" word count in ResultsView
- Talk ratio (should show >0% for user)
- No duplicate words in "You" transcript

---

## Step 5: Commit & PR

```bash
git add -A
git commit -m "feat: integrate DTLN-aec-coreml for echo cancellation

- Add DTLNAec256 Swift package (15 MB)
- Process mic through AEC before sending to Deepgram
- Feed system audio as reference signal
- Convert PCM Int16 ↔ Float32 for AEC
- Graceful degradation if models fail to load

Fixes: User voice not transcribing without headphones (ARA-101)
Performance: <2ms processing, 50dB echo suppression

Co-Authored-By: Claude <noreply@anthropic.com>"

git push -u origin feat/dtln-aec-integration
gh pr create --base main --head feat/dtln-aec-integration
```

---

## Troubleshooting

### Issue: "DTLNAec256 not found"
**Fix:** Make sure you added the package in Xcode (File → Add Package Dependencies)

### Issue: Xcode build error "No such module 'DTLNAecCoreML'"
**Fix:** Product → Clean Build Folder, then rebuild

### Issue: AEC processing slow (>5ms)
**Fix:** Check CoreML compute units in config:
```swift
var config = DTLNAecConfig()
config.computeUnits = .cpuAndNeuralEngine  // Use Neural Engine
let aec = DTLNAecEchoProcessor(config: config)
```

### Issue: Still hearing echo
**Possible causes:**
1. System audio not being fed to AEC (check feedFarEnd calls)
2. Format mismatch (must be 16kHz mono Float32)
3. Buffer alignment issues

**Debug:**
```swift
logger.log(event: "aec_feed_far", layer: "audio",
           details: ["samples": samples.count])
logger.log(event: "aec_process_near", layer: "audio",
           details: ["input": input.count, "output": output.count])
```

---

## Performance Targets

**Expected (Apple M1):**
- AEC processing: <2ms per 8ms frame
- Memory: +15 MB (model)
- Latency: +32ms end-to-end
- CPU: <5% on Apple Silicon

**If slower:**
- Use DTLNAec128 (smaller model)
- Reduce batch size
- Profile with Instruments

---

## Next Steps After Merge

1. Update ARA-101 → Done
2. Close PR #46 (superseded)
3. User testing feedback
4. Monitor performance metrics

---

## Reference

- **DTLN-aec-coreml:** https://github.com/MimicScribe/dtln-aec-coreml
- **Linear:** https://linear.app/aramius/issue/ARA-101
- **Branch:** feat/dtln-aec-integration
