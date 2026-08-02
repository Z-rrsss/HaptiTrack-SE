import SwiftUI

/// The settings panel. Deliberately one screen with no tabs: module 1 has a
/// handful of knobs and hiding them behind navigation would only add clicks.
struct SettingsView: View {

    @ObservedObject var settings: SettingsStore
    @ObservedObject var scrollHaptics: ScrollHapticsController

    var body: some View {
        Form {
            Section {
                Toggle("Scroll haptics", isOn: $settings.isScrollHapticsEnabled)
                statusRow
            }

            Section("Feel") {
                stepSizeSlider
                Picker("Strength", selection: $settings.intensity) {
                    ForEach(HapticIntensity.allCases) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Spacer()
                    Button("Test Pulse") { scrollHaptics.firePreviewPulse() }
                }
            }

            Section("Behaviour") {
                Toggle("Keep ticking while the scroll coasts", isOn: $settings.isMomentumHapticsEnabled)
                Toggle("Also respond to mouse wheels", isOn: $settings.respondsToMouseWheel)
                tickRateSlider
            }

            Section {
                HStack {
                    Text("HaptiTrack \(AppInfo.versionDescription)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { settings.resetToDefaults() }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Rows

    @ViewBuilder
    private var statusRow: some View {
        switch scrollHaptics.status {
        case .running:
            Label("Running", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)

        case .stopped:
            Label("Off", systemImage: "pause.circle")
                .foregroundStyle(.secondary)

        case .waitingForPermission:
            VStack(alignment: .leading, spacing: 8) {
                Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                Text("HaptiTrack watches scroll events to know when to fire a pulse. "
                     + "It never modifies or records them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings…") {
                    AccessibilityAuthorization.openSystemSettings()
                }
            }

        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepSizeSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Notch spacing")
                Spacer()
                Text("\(Int(settings.stepSize.rounded())) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $settings.stepSize,
                in: SettingsStore.stepSizeRange
            ) {
                EmptyView()
            } minimumValueLabel: {
                Text("Fine").font(.caption)
            } maximumValueLabel: {
                Text("Coarse").font(.caption)
            }
        }
    }

    private var tickRateSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Maximum tick rate")
                Spacer()
                Text("\(Int(settings.maximumTickRate.rounded())) / s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $settings.maximumTickRate, in: SettingsStore.tickRateRange)
            Text("Above this speed the notches spread out instead of packing "
                 + "tighter, so a long flick stays a series of ticks rather than a buzz.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
