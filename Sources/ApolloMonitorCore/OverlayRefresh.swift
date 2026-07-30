import Foundation

/// When the overlay's window should be thrown away and rebuilt.
///
/// A long-running instance reached a state where the panel stopped reaching the
/// screen: `show()` ran with a correct frame on a valid screen, `orderFrontRegardless()`
/// returned, and the window server had no window for the process at all. Restarting
/// fixed it instantly. The trigger was never reproduced — it followed ~16 hours of
/// uptime spanning sleep/wake and a display being detached — and a process cannot
/// reliably ask whether its own window reached the screen, because
/// `CGWindowListCopyWindowInfo` answers differently for the calling process.
///
/// So the panel is not repaired on detection; it is replaced across the transitions
/// that preceded the failure. Building one is sub-millisecond, and this never fires
/// during a run of key presses.
public enum OverlayRefresh {
    /// A gap this long since the overlay was last needed means the window has sat
    /// unused across whatever the machine did in between.
    public static let idleThreshold: TimeInterval = 300

    public static func needsFreshPanel(
        lastShownAt: Date,
        now: Date,
        threshold: TimeInterval = idleThreshold
    ) -> Bool {
        now.timeIntervalSince(lastShownAt) >= threshold
    }
}
