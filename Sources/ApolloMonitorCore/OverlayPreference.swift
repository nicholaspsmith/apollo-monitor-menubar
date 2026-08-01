import Foundation

/// Whether the volume overlay is shown when the level changes.
///
/// Stored rather than computed so the choice survives a restart. The store is
/// injectable purely so this is testable without touching the real domain.
public struct OverlayPreference {
    public static let key = "showVolumeOverlay"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Defaults to on. Read via `object(forKey:)` rather than `bool(forKey:)`,
    /// which cannot tell "never set" from "set to false" and reports false for
    /// both — that would silently ship the overlay disabled.
    public var isEnabled: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
