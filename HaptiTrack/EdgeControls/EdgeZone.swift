import CoreGraphics
import Foundation

/// Which strip of the trackpad a gesture runs along.
enum TrackpadEdge: String, CaseIterable, Identifiable, Codable {
    case left
    case right
    case top
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }

    /// The axis a finger travels along once it is in this strip. The vertical
    /// edges are swiped up and down, the horizontal ones left and right.
    var axis: GestureAxis {
        switch self {
        case .left, .right: return .vertical
        case .top, .bottom: return .horizontal
        }
    }

    /// A one-line hint for the settings panel.
    var gestureDescription: String {
        switch axis {
        case .vertical: return "Slide up and down"
        case .horizontal: return "Slide left and right"
        }
    }
}

enum GestureAxis {
    case vertical
    case horizontal
}

/// How often a tick fires relative to the control's own notches.
enum TickDensity: String, CaseIterable, Identifiable, Codable {
    /// One tick per notch of the control — every volume step, say.
    case fullStep
    /// Two ticks per notch, for a finer, more continuous feel.
    case halfStep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullStep: return "Every step"
        case .halfStep: return "Every half step"
        }
    }

    /// Multiplies the control's quantum to give the working step.
    var quantumMultiplier: Double {
        switch self {
        case .fullStep: return 1
        case .halfStep: return 0.5
        }
    }
}

/// Everything the user can configure about one edge.
///
/// Distances are in millimetres so the same numbers feel the same on any
/// trackpad, whatever its resolution or size.
struct EdgeZoneConfiguration: Codable, Equatable, Identifiable {

    var edge: TrackpadEdge

    /// What this edge drives. `.none` switches the edge off — there is no
    /// separate enabled flag, because an edge assigned to nothing is off by
    /// definition and two ways of saying so would only fall out of step.
    var control: ControlIdentifier = .none

    /// How deep the sensitive strip reaches in from the edge, in millimetres.
    var margin: Double = 10

    /// How far a finger has to travel, in millimetres, to sweep the control
    /// from one end of its range to the other.
    var travelForFullRange: Double = 70

    var tickDensity: TickDensity = .fullStep

    /// Swaps which way is "more". Handy if an edge reads backwards on your
    /// hardware, and the natural preference for the horizontal edges.
    var isInverted: Bool = false

    var id: String { edge.rawValue }

    var isEnabled: Bool { control != .none }

    static let marginRange: ClosedRange<Double> = 3...30
    static let travelRange: ClosedRange<Double> = 20...200

    /// The defaults asked for by the roadmap: the right edge is the one a right
    /// handed user reaches first, so it gets volume; brightness goes opposite
    /// it; the horizontal edges stay unassigned until someone wants them.
    static func defaults() -> [EdgeZoneConfiguration] {
        [
            EdgeZoneConfiguration(edge: .left, control: .brightness),
            EdgeZoneConfiguration(edge: .right, control: .volume),
            EdgeZoneConfiguration(edge: .top, control: .none),
            EdgeZoneConfiguration(edge: .bottom, control: .none),
        ]
    }

    // MARK: - Geometry

    /// Whether a normalised position falls inside this edge's strip.
    ///
    /// - Parameter slack: Extra millimetres of tolerance, used to hold on to a
    ///   gesture that has already started so a slightly wandering finger does
    ///   not cancel it.
    func contains(_ position: CGPoint, surface: TrackpadSurfaceSize, slack: Double = 0) -> Bool {
        let depth = margin + slack

        switch edge {
        case .left:
            return Double(position.x) * surface.width <= depth
        case .right:
            return (1 - Double(position.x)) * surface.width <= depth
        case .bottom:
            return Double(position.y) * surface.height <= depth
        case .top:
            return (1 - Double(position.y)) * surface.height <= depth
        }
    }

    /// Signed distance travelled along this edge's axis, in millimetres.
    ///
    /// Positive means "more": up on a vertical edge, right on a horizontal one,
    /// before `isInverted` is applied.
    func travel(from start: CGPoint, to end: CGPoint, surface: TrackpadSurfaceSize) -> Double {
        let distance: Double
        switch edge.axis {
        case .vertical:
            distance = Double(end.y - start.y) * surface.height
        case .horizontal:
            distance = Double(end.x - start.x) * surface.width
        }
        return isInverted ? -distance : distance
    }
}
