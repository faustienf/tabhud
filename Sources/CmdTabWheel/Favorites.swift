import AppKit

/// Windows picked with ★ on the wheel, and whether ⌘Tab shows only them. Both outlive a
/// restart of the app: a window keeps its ID for as long as it exists. Windows of apps that
/// quit meanwhile are dropped on launch.
@MainActor
final class Favorites {
    private static let windowsKey = "favoriteWindows"
    private static let isShownKey = "favoritesShown"
    private let defaults: UserDefaults
    /// Window → the app it belongs to. Both have to match: after a restart of the Mac, a stored
    /// window ID can belong to some other app's window.
    private(set) var windows: [CGWindowID: pid_t]
    /// ⌘Tab opens the way ⌘Space last left it.
    var isShown: Bool {
        didSet { defaults.set(isShown, forKey: Self.isShownKey) }
    }

    init(defaults: UserDefaults = .standard,
         isRunning: (pid_t) -> Bool = { NSRunningApplication(processIdentifier: $0) != nil }) {
        self.defaults = defaults
        isShown = defaults.bool(forKey: Self.isShownKey)
        // A property list has string keys only: "window ID" → pid.
        let stored = defaults.dictionary(forKey: Self.windowsKey) as? [String: Int] ?? [:]
        windows = [:]
        for (id, pid) in stored {
            guard let id = CGWindowID(id), let pid = pid_t(exactly: pid), isRunning(pid) else { continue }
            windows[id] = pid
        }
    }

    func save(_ windows: [CGWindowID: pid_t]) {
        guard windows != self.windows else { return }
        self.windows = windows
        defaults.set(Dictionary(uniqueKeysWithValues: windows.map { (String($0.key), Int($0.value)) }),
                     forKey: Self.windowsKey)
    }
}
