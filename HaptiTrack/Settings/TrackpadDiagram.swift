import SwiftUI

/// Which edge the trackpad diagram lights up.
///
/// This lives apart from the view because it is a rule, not a drawing: the
/// diagram has to agree with whatever the form is showing at that instant, and
/// the rule for "whatever the form is showing" is worth being able to test
/// without a window.
struct EdgeHighlight: Equatable {

    /// The edge whose settings the form is currently displaying.
    var selected: TrackpadEdge

    /// The edge the pointer is resting on in the diagram, if any.
    var hovered: TrackpadEdge?

    /// The edge to light up.
    ///
    /// Hover wins over selection: pointing at a side is a question about *that*
    /// side, and answering the question being asked now beats reflecting the
    /// one asked a moment ago. Letting go of the hover falls back to the
    /// selection rather than to nothing, so the diagram is never dark.
    var edge: TrackpadEdge { hovered ?? selected }

    func isHighlighted(_ edge: TrackpadEdge) -> Bool { self.edge == edge }
}

/// A scale drawing of the trackpad, with the edge being configured lit up.
///
/// Everything is derived from `TrackpadSurfaceSize`, so the rectangle carries
/// the proportions of the trackpad actually attached — a Magic Trackpad is
/// visibly squarer than a built-in one — and each strip is drawn at the depth
/// its `margin` really covers rather than at some fixed decorative width. A
/// 3 mm strip looks like the sliver it is.
///
/// The diagram is also a control: hovering a side previews it and clicking one
/// selects it, which is a more direct way of saying "that edge" than the picker
/// above it.
struct TrackpadDiagram: View {

    var zones: [EdgeZoneConfiguration]
    var highlight: EdgeHighlight
    var surface: TrackpadSurfaceSize = .fallback
    var onHover: (TrackpadEdge?) -> Void = { _ in }
    var onSelect: (TrackpadEdge) -> Void = { _ in }

    /// Force Touch trackpads have a corner radius of a few millimetres.
    private static let cornerRadiusFraction: Double = 0.045

    /// Below this the pointer cannot realistically hit a strip, so the
    /// invisible hit area is grown to it while the drawn strip stays true.
    private static let minimumHitDepth: Double = 22

    private static let transition: Animation = .easeInOut(duration: 0.22)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radius = min(size.width, size.height) * Self.cornerRadiusFraction
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

            ZStack {
                shape.fill(Color.secondary.opacity(0.08))

                ZStack {
                    ForEach(TrackpadEdge.allCases) { edge in
                        strip(for: edge, in: size)
                    }
                }
                .clipShape(shape)

                shape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)

                ForEach(TrackpadEdge.allCases) { edge in
                    hitArea(for: edge, in: size)
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .animation(Self.transition, value: highlight.edge)
        .accessibilityElement()
        .accessibilityLabel("Trackpad")
        .accessibilityValue("\(highlight.edge.displayName) edge selected")
    }

    private var aspectRatio: Double {
        guard surface.width > 0, surface.height > 0 else {
            return TrackpadSurfaceSize.fallback.width / TrackpadSurfaceSize.fallback.height
        }
        return surface.width / surface.height
    }

    // MARK: - Strips

    @ViewBuilder
    private func strip(for edge: TrackpadEdge, in size: CGSize) -> some View {
        let zone = zone(for: edge)
        let frame = stripFrame(for: zone, in: size, minimumDepth: 3)
        let isHighlighted = highlight.isHighlighted(edge)

        Rectangle()
            .fill(color(for: zone, isHighlighted: isHighlighted))
            // The glow is what makes the change read as something switching on
            // rather than as a swatch quietly changing colour.
            .shadow(
                color: isHighlighted ? Color.blue.opacity(0.7) : .clear,
                radius: isHighlighted ? 6 : 0
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    /// Blue for the edge being configured, near-invisible for an edge assigned
    /// to nothing, a neutral grey for the rest.
    private func color(for zone: EdgeZoneConfiguration, isHighlighted: Bool) -> Color {
        if isHighlighted {
            return .blue.opacity(zone.isEnabled ? 0.85 : 0.5)
        }
        return .secondary.opacity(zone.isEnabled ? 0.3 : 0.12)
    }

    private func stripFrame(
        for zone: EdgeZoneConfiguration,
        in size: CGSize,
        minimumDepth: Double
    ) -> CGRect {
        let fraction = zone.stripFraction(surface: surface)

        switch zone.edge {
        case .left, .right:
            let depth = max(fraction * size.width, minimumDepth)
            let x = zone.edge == .left ? 0 : size.width - depth
            return CGRect(x: x, y: 0, width: depth, height: size.height)

        case .top, .bottom:
            let depth = max(fraction * size.height, minimumDepth)
            // The diagram is drawn the way the trackpad is seen from above, so
            // "top" is the top of the view. The model's y axis runs the other
            // way, which matters to the gesture engine and not to this.
            let y = zone.edge == .top ? 0 : size.height - depth
            return CGRect(x: 0, y: y, width: size.width, height: depth)
        }
    }

    // MARK: - Hit testing

    /// An invisible, comfortably sized target over each side. The horizontal
    /// sides are inset by the vertical ones' depth so the corners belong to
    /// exactly one edge and hovering near one does not flicker between two.
    private func hitArea(for edge: TrackpadEdge, in size: CGSize) -> some View {
        let depth = Self.minimumHitDepth
        let frame: CGRect

        switch edge {
        case .left:
            frame = CGRect(x: 0, y: 0, width: depth, height: size.height)
        case .right:
            frame = CGRect(x: size.width - depth, y: 0, width: depth, height: size.height)
        case .top:
            frame = CGRect(x: depth, y: 0, width: max(size.width - 2 * depth, 0), height: depth)
        case .bottom:
            frame = CGRect(
                x: depth,
                y: size.height - depth,
                width: max(size.width - 2 * depth, 0),
                height: depth
            )
        }

        return Color.clear
            .contentShape(Rectangle())
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .onHover { isInside in onHover(isInside ? edge : nil) }
            .onTapGesture { onSelect(edge) }
            .help("\(edge.displayName) edge — \(zone(for: edge).control.displayName)")
    }

    private func zone(for edge: TrackpadEdge) -> EdgeZoneConfiguration {
        zones.first { $0.edge == edge } ?? EdgeZoneConfiguration(edge: edge)
    }
}

#Preview {
    TrackpadDiagram(
        zones: EdgeZoneConfiguration.defaults(),
        highlight: EdgeHighlight(selected: .right)
    )
    .frame(width: 260)
    .padding()
}
