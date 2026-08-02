import SwiftUI

/// What the intro overlay is showing right now.
///
/// The controller owns the clock and writes to this; the view only draws it.
/// Keeping the animation state here rather than in `@State` inside the view is
/// what lets a haptic pulse, a click and a scale bump be one event instead of
/// three things that happen to be scheduled at about the same time.
@MainActor
final class LaunchOverlayModel: ObservableObject {

    /// The whole overlay, faded in at the start and out at the end.
    @Published var opacity: Double = 0

    @Published var titleScale: Double = 0.92

    /// The name rests below full strength so a pulse has somewhere to go.
    @Published var titleOpacity: Double = 0

    static let restingTitleOpacity: Double = 0.78
    static let pulsedTitleScale: Double = 1.1
}

/// The launch flourish: a purple vignette closing in from the edges of the
/// screen, the app name in the middle, two pulses, gone.
///
/// The centre is left clear on purpose — this sits over whatever the user was
/// already doing, and briefly tinting the edges of their screen is a very
/// different thing from covering their work with a splash screen.
struct LaunchOverlayView: View {

    @ObservedObject var model: LaunchOverlayModel

    private static let violet = AppColor.accent

    /// How far in from each edge the tint reaches, as a fraction of the
    /// dimension it runs into. The sides come in less far than the top and
    /// bottom because a screen is wider than it is tall and matching the
    /// fractions would make the vignette lopsided.
    private static let sideDepth: Double = 0.18
    private static let topDepth: Double = 0.22

    /// Strength right at the edge of the screen. The four bands overlap in the
    /// corners, which is what makes those the deepest part of the tint without
    /// any of it being drawn twice on purpose.
    private static let edgeOpacity: Double = 0.55

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                // Four bands rather than one radial gradient: a radial one
                // sized to reach the edges ends up washing the whole screen
                // purple, and the point of this is to tint the *frame* of the
                // screen and leave what the user was looking at alone.
                band(.top, in: size)
                band(.bottom, in: size)
                band(.leading, in: size)
                band(.trailing, in: size)

                Text(AppInfo.name)
                    .font(.system(size: 68, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Self.violet.opacity(0.9), radius: 26)
                    .shadow(color: .black.opacity(0.35), radius: 10)
                    .scaleEffect(model.titleScale)
                    .opacity(model.titleOpacity)
            }
            .frame(width: size.width, height: size.height)
        }
        .opacity(model.opacity)
        .ignoresSafeArea()
        // Belt and braces: the window ignores mouse events too, but a
        // full-screen overlay that could swallow a click is worth refusing
        // twice over.
        .allowsHitTesting(false)
    }

    /// One edge's worth of tint, fading from the screen edge inwards.
    private func band(_ edge: Edge, in size: CGSize) -> some View {
        let isHorizontal = edge == .leading || edge == .trailing
        let depth = isHorizontal
            ? size.width * Self.sideDepth
            : size.height * Self.topDepth

        // The falloff is front-loaded rather than linear: most of the colour
        // sits in the first third of the band, so the tint hugs the edge and
        // the middle of the screen stays genuinely clear instead of merely
        // paler than the rim.
        let gradient = LinearGradient(
            stops: [
                .init(color: Self.violet.opacity(Self.edgeOpacity), location: 0),
                .init(color: Self.violet.opacity(Self.edgeOpacity * 0.3), location: 0.35),
                .init(color: Self.violet.opacity(0), location: 1),
            ],
            startPoint: startPoint(for: edge),
            endPoint: endPoint(for: edge)
        )

        return gradient
            .frame(
                width: isHorizontal ? depth : size.width,
                height: isHorizontal ? size.height : depth
            )
            .frame(width: size.width, height: size.height, alignment: alignment(for: edge))
    }

    private func startPoint(for edge: Edge) -> UnitPoint {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    private func endPoint(for edge: Edge) -> UnitPoint {
        switch edge {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }

    private func alignment(for edge: Edge) -> Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}
