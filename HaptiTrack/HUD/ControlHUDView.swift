import SwiftUI

/// What the HUD is showing, and whether it is out.
///
/// The controller owns both and the view only draws them, the same arrangement
/// the launch overlay uses: the window, the animation and the auto-dismiss all
/// have to agree, and they can only do that if one object is in charge of them.
@MainActor
final class ControlHUDModel: ObservableObject {

    @Published var presentation = ControlHUDPresentation(
        title: "", symbolName: "circle", value: 0
    )

    /// Whether the panel is rolled down below the notch.
    @Published var isExpanded = false

    /// How much of the panel the camera housing covers. Comes from the screen
    /// the HUD is currently on, so it is right on an external display too.
    @Published var notchHeight: Double = NotchGeometry.standard.height
}

/// The overlay that rolls down out of the notch while an edge is being swiped.
///
/// It is drawn in black on purpose. On a MacBook Pro the top of it sits behind
/// the camera housing, and any other colour would show the seam; on a Mac
/// without a notch the same black shape reads as one anyway, which is what
/// makes the two look identical.
struct ControlHUDView: View {

    @ObservedObject var model: ControlHUDModel

    /// The part below the notch: one row of text and the bar under it.
    static let contentHeight: Double = 46

    private static let cornerRadius: Double = 18

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: Self.cornerRadius,
            bottomTrailingRadius: Self.cornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
        let revealed = model.isExpanded ? Self.contentHeight : 0

        VStack(spacing: 0) {
            // The notch itself: nothing is drawn here, it is the black behind
            // it that matters.
            Color.clear.frame(height: model.notchHeight)

            content
                .frame(height: Self.contentHeight)
                .opacity(model.isExpanded ? 1 : 0)
        }
        .frame(height: model.notchHeight + revealed, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        // Stick to the top of the panel, so growing and shrinking happens at
        // the bottom edge — the shape rolls down out of the notch rather than
        // sliding down the screen.
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// The HUD is as wide as the notch it grows out of, which is around 185
    /// points and not negotiable, so the row has to fit in what is left after
    /// the padding. "Keyboard Backlight" is the longest label and the one this
    /// is sized against; anything longer shrinks rather than truncating,
    /// because a clipped name reads as a bug and a slightly smaller one does
    /// not.
    private var content: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: model.presentation.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)

                Text(model.presentation.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Text(model.presentation.percentageText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .layoutPriority(1)
            }
            .foregroundStyle(.white)

            bar
        }
        .padding(.horizontal, 11)
        .padding(.top, 3)
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(AppColor.accent)
                    // A sliver at zero, so the bar reads as a bar at rest
                    // rather than as a missing one.
                    .frame(width: max(proxy.size.width * model.presentation.value, 3))
            }
        }
        .frame(height: 4)
        // Ticks arrive one notch at a time; sliding between them keeps the bar
        // from stepping while the finger is moving smoothly.
        .animation(.easeOut(duration: 0.12), value: model.presentation.value)
    }
}

#Preview {
    let model = ControlHUDModel()
    model.presentation = ControlHUDPresentation(
        title: "Brightness", symbolName: "sun.max.fill", value: 0.62
    )
    model.isExpanded = true

    return ControlHUDView(model: model)
        .frame(width: 260, height: 78)
        .background(Color.gray)
}
