//
//  AudioSettingsView.swift
//  Empy_Swift
//
//  Microphone picker, level meter, mic test, and speaker test.
//  Reused in SetupView (before call) and RecordingView sidebar popover (during call).
//

import SwiftUI

struct AudioSettingsView: View {
    /// Pass true when the recording session is active — disables the mic test
    var isInSession: Bool = false

    @ObservedObject private var deviceManager = AudioDeviceManager.shared
    @StateObject private var micTester     = MicTester()
    @StateObject private var speakerTester = SpeakerTester()

    /// Stored via UserDefaults (key matches SessionManager)
    @AppStorage("preferredInputDeviceUID") private var preferredInputUID: String = ""
    @AppStorage("preferredOutputDeviceUID") private var preferredOutputUID: String = ""

    private var selectedInputDevice: AudioDevice? {
        deviceManager.inputDevices.first { $0.uid == preferredInputUID }
    }

    // Backwards-compat alias used by micTestButton
    private var selectedDevice: AudioDevice? { selectedInputDevice }

    private var isBusy: Bool {
        micTester.state != .idle || speakerTester.isPlaying || isInSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.md) {
            microphoneSection
            Divider()
            outputSection
            Divider()
            speakerSection
        }
    }

    // MARK: - Microphone section

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.sm) {
            Label("Microphone", systemImage: "mic.fill")
                .font(.empyLabel)
                .foregroundColor(.primary)

            if deviceManager.inputDevices.isEmpty {
                Text("No microphones found")
                    .font(.empyCaption)
                    .foregroundColor(.secondary)
            } else {
                Picker("Microphone", selection: $preferredInputUID) {
                    Text("System Default").tag("")
                    ForEach(deviceManager.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            // Mic test button + feedback
            micTestButton
        }
    }

    @ViewBuilder
    private var micTestButton: some View {
        switch micTester.state {
        case .idle:
            Button {
                micTester.startTest(device: selectedDevice)
            } label: {
                Label("Test Microphone", systemImage: "waveform.circle")
                    .font(.empyCaption)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)

        case .recording(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recording…")
                        .font(.empyCaption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fs", progress * 3))
                        .font(.empyCaption.monospacedDigit())
                        .foregroundColor(.secondary)
                    cancelMicTestButton
                }
                // Level meter
                LevelMeterView(level: micTester.level)
                // Progress
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.red)
            }

        case .playing(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Playing back…")
                        .font(.empyCaption)
                        .foregroundColor(.secondary)
                    Spacer()
                    cancelMicTestButton
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }
    }

    private var cancelMicTestButton: some View {
        Button {
            micTester.cancel()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Output (System Audio) section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.sm) {
            Label("System Audio Output", systemImage: "waveform.path.ecg")
                .font(.empyLabel)
                .foregroundColor(.primary)

            Text("ScreenCaptureKit records audio routed to this device.")
                .font(.empyCaption)
                .foregroundColor(.secondary)

            if deviceManager.outputDevices.isEmpty {
                Text("No output devices found")
                    .font(.empyCaption)
                    .foregroundColor(.secondary)
            } else {
                Picker("System Audio Output", selection: $preferredOutputUID) {
                    Text("System Default").tag("")
                    ForEach(deviceManager.outputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: preferredOutputUID) { uid in
                    guard !uid.isEmpty,
                          let device = deviceManager.outputDevices.first(where: { $0.uid == uid })
                    else { return }
                    try? AudioDeviceManager.shared.setSystemDefaultOutputDevice(device)
                }
            }
        }
    }

    // MARK: - Speaker section

    private var speakerSection: some View {
        VStack(alignment: .leading, spacing: EmpySpacing.sm) {
            Label("Speaker", systemImage: "speaker.wave.2.fill")
                .font(.empyLabel)
                .foregroundColor(.primary)

            if speakerTester.isPlaying {
                HStack(spacing: EmpySpacing.xs) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Playing test tone…")
                        .font(.empyCaption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        speakerTester.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    speakerTester.playTestSound()
                } label: {
                    Label("Test Speaker", systemImage: "speaker.wave.3")
                        .font(.empyCaption)
                }
                .buttonStyle(.bordered)
                .disabled(micTester.state != .idle)
            }
        }
    }
}

// MARK: - Level meter

private struct LevelMeterView: View {
    let level: Float  // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        AudioSettingsView()
            .padding()
            .frame(width: 320)
        Divider()
        AudioSettingsView(isInSession: true)
            .padding()
            .frame(width: 320)
    }
}
