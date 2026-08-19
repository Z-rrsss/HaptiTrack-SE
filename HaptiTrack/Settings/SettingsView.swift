import SwiftUI

/// The settings window.
///
/// One tab per module. Module 1 fitted on a single screen; module 2 has four
/// independently configurable edges, and putting eleven more controls under the
/// scroll settings would have turned a short panel into a scrolling one.
struct SettingsView: View {

    @ObservedObject var settings: SettingsStore
    @ObservedObject var scrollHaptics: ScrollHapticsController
    @ObservedObject var edgeControls: EdgeControlsController

    var body: some View {
        TabView {
            ScrollSettingsView(settings: settings, scrollHaptics: scrollHaptics)
                .tabItem { Label("Scrolling", systemImage: "hand.tap") }

            EdgeSettingsView(settings: settings, edgeControls: edgeControls)
                .tabItem { Label("Edges", systemImage: "rectangle.inset.filled") }
        }
        .frame(width: 460)
        // A TabView has no height of its own: it takes whatever it is offered,
        // and what the window offers is the screen. Both tabs already ask for
        // their ideal height, so this passes the taller one up instead of
        // letting the window grow to the full height of the display.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Module 1: haptic feedback for trackpad scrolling.
struct ScrollSettingsView: View {

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
                    Text("\(AppInfo.name) \(AppInfo.versionDescription)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { settings.resetToDefaults() }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
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
            PermissionNotice(
                title: "Accessibility permission required",
                explanation: "HaptiTrack watches scroll events to know when to fire a pulse. "
                    + "It never modifies or records them.",
                action: AccessibilityAuthorization.openSystemSettings
            )

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

/// A missing-permission row: what is needed, why, and a way to go and grant it.
struct PermissionNotice: View {
    let title: String
    let explanation: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings…", action: action)
        }
    }
}
