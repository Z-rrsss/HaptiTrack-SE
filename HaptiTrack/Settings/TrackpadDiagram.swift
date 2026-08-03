import SwiftUI

/// Where the four strips sit inside the drawn rectangle, and which one a click
/// lands on.
///
/// This is the diagram's geometry with the drawing taken out, which is what
/// makes it testable: "clicking near the left border selects the left edge" is
/// a claim about arithmetic, and proving it should not need a window, a mouse
/// or a running app.
struct TrackpadDiagramLayout: Equatable {

    var zones: [EdgeZoneConfiguration]
    var surface: TrackpadSurfaceSize
    var size: CGSize

    /// Thinner than this and the strip would be invisible, so it is drawn at
    /// this depth even when the real margin is smaller.
    static let minimumDrawnDepth: Double = 3

    /// Thinner than this and the strip could not be clicked, so the click
    /// target is grown to it while the drawn strip stays true to the margin.
    static let minimumClickDepth: Double = 22

    func zone(for edge: TrackpadEdge) -> EdgeZoneConfiguration {
        zones.first { $0.edge == edge } ?? EdgeZoneConfiguration(edge: edge)
    }

    /// The strip as drawn: as deep as the margin it represents.
    func stripFrame(for edge: TrackpadEdge) -> CGRect {
        frame(for: edge, depth: max(depth(for: edge), Self.minimumDrawnDepth))
    }

    /// The edge a click at `point` belongs to, or `nil` for the middle of the
    /// trackpad, which is not an edge and should not select one.
    ///
    /// The vertical edges are tested first, so a click in a corner goes to the
    /// left or right edge — the same way the strips are drawn, with the
    /// vertical ones running the full height and the horizontal ones tucked
    /// between them.
    func edge(at point: CGPoint) -> TrackpadEdge? {
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else {
            return nil
        }

        if point.x <= clickDepth(for: .left) { return .left }
        if point.x >= size.width - clickDepth(for: .right) { return .right }
        if point.y <= clickDepth(for: .top) { return .top }
        if point.y >= size.height - clickDepth(for: .bottom) { return .bottom }
        return nil
    }

    /// The proportions of the trackpad itself, for the view to size itself by.
    ///
    /// Always landscape. A trackpad is wider than it is tall, so a surface that
    /// says otherwise is not a trackpad — it is the wrong device, or a pair of
    /// numbers the wrong way round — and drawing a portrait one would be
    /// drawing hardware that does not exist. Flipping the ratio keeps how
    /// elongated the surface is while refusing to stand it on end.
    var aspectRatio: Double {
        let fallback = TrackpadSurfaceSize.fallback.width / TrackpadSurfaceSize.fallback.height
        guard surface.width > 0, surface.height > 0 else { return fallback }

        let ratio = surface.width / surface.height
        let landscape = max(ratio, 1 / ratio)

        // A square is no more a trackpad than a portrait rectangle is, so
        // there is nothing to preserve the shape of: draw the trackpad this
        // app is for.
        return landscape > 1 ? landscape : fallback
    }

    /// How tall the diagram is when drawn `width` points wide.
    ///
    /// Callers use this to give the diagram a definite size. Its body is a
    /// `GeometryReader`, which has no size of its own and grows into whatever
    /// it is offered, so leaving the height to the surrounding layout is how
    /// a settings panel ends up the height of the screen.
    static func height(forWidth width: Double, surface: TrackpadSurfaceSize) -> Double {
        let layout = TrackpadDiagramLayout(zones: [], surface: surface, size: .zero)
        return width / layout.aspectRatio
    }

    // MARK: - Depths

    /// How deep the strip runs, in points, at the size the diagram is drawn.
    private func depth(for edge: TrackpadEdge) -> Double {
        let fraction = zone(for: edge).stripFraction(surface: surface)
        return fraction * (edge.axis == .vertical ? size.width : size.height)
    }

    private func clickDepth(for edge: TrackpadEdge) -> Double {
        max(depth(for: edge), Self.minimumClickDepth)
    }

    private func frame(for edge: TrackpadEdge, depth: Double) -> CGRect {
        switch edge {
        case .left:
            return CGRect(x: 0, y: 0, width: depth, height: size.height)
        case .right:
            return CGRect(x: size.width - depth, y: 0, width: depth, height: size.height)
        case .top:
            // The diagram is drawn the way the trackpad is seen from above, so
            // "top" is the top of the view. The model's y axis runs the other
            // way, which matters to the gesture engine and not to this.
            return CGRect(x: 0, y: 0, width: size.width, height: depth)
        case .bottom:
            return CGRect(x: 0, y: size.height - depth, width: size.width, height: depth)
        }
    }
}

/// A scale drawing of the trackpad, with the edge being configured lit up.
///
/// Everything is derived from `TrackpadSurfaceSize`, so the rectangle carries
/// the proportions of the trackpad actually attached — a Magic Trackpad is
/// visibly squarer than a built-in one — and each strip is drawn at the depth
/// its `margin` really covers rather than at some fixed decorative width. A
/// 3 mm strip looks like the sliver it is.
///
/// The diagram is also a control: clicking a side selects it, which is a more
/// direct way of saying "that edge" than the picker above it. It deliberately
/// does not react to the pointer merely passing over it — the lit edge means
/// "this is the one you are editing", and a diagram that lights up under the
/// cursor would be answering a question nobody asked.
struct TrackpadDiagram: View {

    var zones: [EdgeZoneConfiguration]

    /// The edge being edited. The one thing that lights up, and the only thing
    /// that decides it.
    var selectedEdge: TrackpadEdge
    var surface: TrackpadSurfaceSize = .fallback
    var onSelect: (TrackpadEdge) -> Void = { _ in }

    /// Force Touch trackpads have a corner radius of a few millimetres.
    private static let cornerRadiusFraction: Double = 0.045

    private static let transition: Animation = .easeInOut(duration: 0.22)

    var body: some View {
        GeometryReader { proxy in
            let layout = TrackpadDiagramLayout(zones: zones, surface: surface, size: proxy.size)
            let radius = min(proxy.size.width, proxy.size.height) * Self.cornerRadiusFraction
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

            ZStack {
                shape.fill(Color.secondary.opacity(0.08))

                ZStack {
                    ForEach(TrackpadEdge.allCases) { edge in
                        strip(for: edge, layout: layout)
                    }
                }
                .clipShape(shape)

                shape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            }
            .contentShape(shape)
            .onTapGesture(coordinateSpace: .local) { point in
                guard let edge = layout.edge(at: point) else { return }
                onSelect(edge)
            }
        }
        .aspectRatio(layoutAspectRatio, contentMode: .fit)
        .animation(Self.transition, value: selectedEdge)
        .accessibilityElement()
        .accessibilityLabel("Trackpad")
        .accessibilityValue("\(selectedEdge.displayName) edge selected")
    }

    private var layoutAspectRatio: Double {
        TrackpadDiagramLayout(zones: zones, surface: surface, size: .zero).aspectRatio
    }

    // MARK: - Strips

    private func strip(for edge: TrackpadEdge, layout: TrackpadDiagramLayout) -> some View {
        let zone = layout.zone(for: edge)
        let frame = layout.stripFrame(for: edge)
        let isLit = edge == selectedEdge

        return Rectangle()
            .fill(color(for: zone, isLit: isLit))
            // The glow is what makes the change read as something switching on
            // rather than as a swatch quietly changing colour.
            .shadow(
                color: isLit ? AppColor.accent.opacity(0.7) : .clear,
                radius: isLit ? 6 : 0
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    /// The app's purple for the edge being configured, near-invisible for an
    /// edge assigned to nothing, a neutral grey for the rest.
    private func color(for zone: EdgeZoneConfiguration, isLit: Bool) -> Color {
        if isLit {
            return AppColor.accent.opacity(zone.isEnabled ? 0.95 : 0.55)
        }
        return .secondary.opacity(zone.isEnabled ? 0.3 : 0.12)
    }
}

#Preview {
    TrackpadDiagram(zones: EdgeZoneConfiguration.defaults(), selectedEdge: .right)
        .frame(width: 260)
        .padding()
}
