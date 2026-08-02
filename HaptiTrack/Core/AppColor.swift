import SwiftUI

/// The one purple HaptiTrack uses for itself.
///
/// It means "this is the thing you are working on, or the thing that just
/// moved": the lit edge in the trackpad diagram, the vignette at launch, the
/// bar in the HUD. One constant rather than a literal in each place, because
/// three purples that are nearly the same is worse than one that is.
///
/// Deliberately not the system accent colour. That one belongs to the user, it
/// can be any of eight hues or follow the wallpaper, and an app whose own
/// identity changes colour with a system preference does not have one.
enum AppColor {
    static let accent = Color(red: 0.45, green: 0.18, blue: 0.85)
}
