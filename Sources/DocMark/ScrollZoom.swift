import AppKit

/// A document view that zooms around a point in window coordinates.
protocol ScrollZooming {
    func zoom(by factor: CGFloat, at windowPoint: NSPoint?)
}

extension NSEvent {
    /// How much a Command-scroll should zoom by. It is nil without Command, when the event should
    /// scroll as usual, and 1 for the coasting after a flick, which would keep zooming on its own.
    var commandScrollZoom: CGFloat? {
        guard modifierFlags.contains(.command) else { return nil }
        guard momentumPhase.isEmpty else { return 1 }
        // A trackpad reports pixels and a mouse wheel reports whole lines.
        return pow(hasPreciseScrollingDeltas ? 1.01 : 1.1, scrollingDeltaY)
    }
}
