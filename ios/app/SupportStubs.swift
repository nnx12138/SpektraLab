//  SupportStubs.swift — iOS stand-ins for the two macOS-window affordances
//  the shared sources reference.
//
//  * `WindowDragHandle` (Windows/EditorWindow.swift) is the rail header's
//    invisible drag surface; windows are moved by the system on iOS, so it
//    degrades to nothing.
//  * `TrafficLightAlignment.rowWidth` (Windows/TrafficLights.swift) is the
//    width the traffic lights reserve in a header row; iOS has no window
//    buttons, but the metric still reserves the space so the shared layout
//    constants keep their Mac-measured relationships.

import SwiftUI

/// The rail header's drag surface. iOS windows are not user-movable; an
/// empty view keeps `.background(WindowDragHandle())` valid on both rails.
struct WindowDragHandle: View {
    var body: some View {
        Color.clear
    }
}

/// The geometry the macOS traffic lights occupy, reduced on iOS to the row
/// width the shared `Theme.Metric` arithmetic consumes.
enum TrafficLightAlignment {
    /// The macOS buttons span 54pt (spacing 20 × 2 + diameter 14); keeping
    /// the value rather than zeroing it preserves the Mac-measured header
    /// rhythm on iPad, where the rails mirror the Mac's.
    static let rowWidth: CGFloat = 54
}
