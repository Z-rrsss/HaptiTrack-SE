import SwiftUI

/// Module 2: what each edge of the trackpad controls, and how it feels.
///
/// The four edges are configured one at a time behind a segmented picker
/// instead of being stacked. Each edge has five knobs, so showing all four at
/// once would mean twenty controls on one screen — and an edge is something you
/// set up once and then forget, not something you compare side by side.
struct EdgeSettingsView: View {

    @ObservedObject var settings: SettingsStore
    @ObservedObject var edgeControls: EdgeControlsController

    @State private var selectedEdge: TrackpadEdge = .right
    @State private var hoveredEdge: TrackpadEdge?

    private var highlight: EdgeHighlight {
        EdgeHighlight(selected: selectedEdge, hovered: hoveredEdge)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Edge controls", isOn: $settings.areEdgeControlsEnabled)
                statusRow
            }

            Section {
                Picker("Edge", selection: $selectedEdge) {
                    ForEach(TrackpadEdge.allCases) { edge in
                        Text(edge.displayName).tag(edge)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                TrackpadDiagram(
                    zones: settings.edgeZones,
                    highlight: highlight,
                    surface: edgeControls.surface,
                    onHover: { hoveredEdge = $0 },
                    onSelect: { selectedEdge = $0 }
                )
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }

            // The form follows the selection, not the hover: the pointer
            // passing over the diagram should preview an edge, not rearrange
            // the controls under the cursor.
            edgeSection(for: selectedEdge)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - One edge

    @ViewBuilder
    private func edgeSection(for edge: TrackpadEdge) -> some View {
        let zone = binding(for: edge)

        Section(edge.displayName + " edge") {
            Picker("Controls", selection: zone.control) {
                ForEach(ControlIdentifier.allCases) { identifier in
                    Text(identifier.displayName).tag(identifier)
                }
            }

            if !edgeControls.isControlAvailable(zone.wrappedValue.control) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("This control isn't available right now.", systemImage: "exclamationmark.triangle")
                    // Availability is not a fixed property of the Mac: an
                    // external display used as the audio output often exposes
                    // no volume at all, and brightness follows whichever
                    // display is currently the main one.
                    Text("Availability depends on the display and audio device in use. "
                         + "Reopen this panel after switching devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }

            if zone.wrappedValue.isEnabled {
                millimetreSlider(
                    title: "Active strip",
                    value: zone.margin,
                    range: EdgeZoneConfiguration.marginRange,
                    caption: "How far in from the \(edge.displayName.lowercased()) edge a finger "
                        + "counts as being on the strip. \(edge.gestureDescription) inside it."
                )

                millimetreSlider(
                    title: "Full sweep",
                    value: zone.travelForFullRange,
                    range: EdgeZoneConfiguration.travelRange,
                    caption: "Finger travel needed to move the control across its whole range. "
                        + "Longer means finer adjustment."
                )

                Picker("Haptic ticks", selection: zone.tickDensity) {
                    ForEach(TickDensity.allCases) { density in
                        Text(density.displayName).tag(density)
                    }
                }

                Toggle("Reverse direction", isOn: zone.isInverted)

                HStack {
                    Spacer()
                    Button("Test") { edgeControls.firePreviewTicks() }
                        .help("Plays the tick pattern without moving the control.")
                }
            }
        }
    }

    private func millimetreSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        caption: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) mm")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusRow: some View {
        switch edgeControls.status {
        case .running:
            Label("Running", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)

        case .stopped:
            Label("Off", systemImage: "pause.circle")
                .foregroundStyle(.secondary)

        case .waitingForPermission:
            PermissionNotice(
                title: "Input Monitoring permission required",
                explanation: "Edge controls need to know where your finger is on the trackpad, "
                    + "which macOS treats as a separate permission from Accessibility.",
                action: InputMonitoringAuthorization.openSystemSettings
            )

        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Binding

    /// Edges live in an array in the store, so editing one means reading it
    /// out, changing a field and writing the whole entry back. This hides that
    /// behind a binding the form can use like any other.
    private func binding(for edge: TrackpadEdge) -> Binding<EdgeZoneConfiguration> {
        Binding(
            get: { settings.zone(for: edge) },
            set: { settings.updateZone($0) }
        )
    }
}
