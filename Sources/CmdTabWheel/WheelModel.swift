import AppKit
import Observation

/// One sector of the wheel: a running app — or one of its windows, when it has several.
struct WheelItem: Identifiable {
    struct ID: Hashable {
        let pid: pid_t
        let window: CGWindowID?
    }

    let pid: pid_t
    let name: String
    let icon: NSImage
    let app: NSRunningApplication
    /// Hidden (⌘H): it has windows, just out of sight and not on the wheel.
    var isHidden = false
    /// Finder can't quit (unless a hidden setting allows it).
    var canQuit = true
    /// The program that started this copy of the app, when it wasn't the user ("chrome-devtools-mcp").
    var launchedBy: String?
    /// The window this sector stands for. nil = the app as a whole (one window or none).
    var window: AppWindow?
    /// "2" on the icon of the app's second window; nil for one-window apps.
    var windowNumber: Int?

    var id: ID { ID(pid: pid, window: window?.id) }
}

extension WheelItem {
    /// The app as a whole: one sector.
    init(app: NSRunningApplication) {
        self.init(
            pid: app.processIdentifier,
            name: app.localizedName ?? app.bundleIdentifier ?? "?",
            icon: app.icon ?? NSImage(),
            app: app,
            isHidden: app.isHidden,
            canQuit: app.bundleIdentifier != "com.apple.finder",
            launchedBy: AppLauncher.name(ofParentOf: app.processIdentifier)
        )
    }
}

/// Wheel state: which apps are on it and which one is selected.
/// `@Observable` makes SwiftUI re-render whatever reads these properties (like a store).
///
/// Mouse selection: a virtual segment goes from the wheel center to the cursor; the sector it
/// crosses is selected. Only the direction matters, so the cursor can be anywhere on screen.
/// Cursor inside the hub crosses nothing → no selection.
/// Points are relative to the wheel center, y pointing down (SwiftUI-style).
@MainActor
@Observable
final class WheelModel {
    /// How far the cursor has to move before the mouse takes over the selection.
    static let pointerActivationDistance: CGFloat = 2

    let layout: WheelLayout
    private(set) var items: [WheelItem] = []
    /// Use the unfiltered ring's density in both modes, so ⌘Space never enlarges icons.
    private(set) var iconSize: CGFloat = 0
    private(set) var selectedIndex: Int?
    /// Visual feedback only: grows beyond the rim; keyboard uses the midpoint.
    private(set) var selectionReach: CGFloat = 0.5
    /// Window screenshots, shown in the hub. Kept between openings so the next ⌘Tab
    /// shows them instantly; refreshed in the background every time the wheel opens.
    private(set) var previews: [PreviewKey: NSImage] = [:]
    /// Each app's windows on the wheel — on screen first, front to back; then on other desktops
    /// and minimized: all of them, or only the favorites (`showsFavorites`).
    private(set) var windows: [pid_t: [AppWindow]] = [:]
    /// Every app and every window, taken when the wheel opens, whichever of them it shows.
    @ObservationIgnored private(set) var allApps: [WheelItem] = []
    @ObservationIgnored private(set) var allWindows: [pid_t: [AppWindow]] = [:]
    /// Windows picked with ★ on the rail, each with its app. Kept between openings.
    private(set) var favorites: [CGWindowID: pid_t]
    /// Only favorite windows are on the wheel; ⌘Space switches.
    private(set) var showsFavorites = false
    /// The favorites when the wheel opened or ⌘Space was pressed: a window un-starred since
    /// keeps its sector until then, so a slip of the mouse can be undone right there.
    @ObservationIgnored private var favoritesOnWheel: [CGWindowID: pid_t] = [:]
    /// The pointer is on this button in the selected sector’s outer rail.
    private(set) var hoveredRailButton: RailButton?

    var selectedItem: WheelItem? { selectedIndex.map { items[$0] } }

    /// The previously used app. A quick ⌘Tab — released without touching anything — goes there.
    private(set) var quickSwitchPID: pid_t?
    /// The window of that app the user was last in, if known.
    private(set) var quickSwitchWindowID: CGWindowID?
    /// The user did something this time: moved the mouse past the threshold or pressed Tab.
    /// After that, releasing ⌘ with nothing selected means "cancel", not "quick switch".
    private(set) var wasTouched = false
    /// A window was closed or an app quit from the wheel, and the user hasn't picked a sector
    /// since. Releasing ⌘ then goes back to where the user was: the selection only stayed
    /// on that app so ⌘W can go on closing its windows, it isn't a choice to switch there.
    /// (Switching to an app whose windows were just closed would even reopen one.)
    @ObservationIgnored private(set) var hasClosedSomething = false

    var quickSwitchItem: WheelItem? {
        guard !wasTouched, let quickSwitchPID else { return nil }
        // An app with several windows: the sector of the window the user left it from, if it's
        // still there. Else its front one — which may be another window: the one left can be
        // behind a full-screen app while another one shows on a second display.
        let appWindows = windows[quickSwitchPID] ?? []
        let window = appWindows.first { $0.id == quickSwitchWindowID }?.id ?? appWindows.first?.id
        return items.first { $0.pid == quickSwitchPID && ($0.window == nil || $0.window?.id == window) }
    }

    // Pointer bookkeeping isn't drawn, so it's not observed (no re-render per mouse move).
    /// Where the cursor was when the wheel opened or Tab was last pressed.
    @ObservationIgnored private var pointerAnchor: CGPoint = .zero
    @ObservationIgnored private var lastPointer: CGPoint = .zero
    /// The cursor moved far enough from the anchor — the mouse drives the selection.
    @ObservationIgnored private var isPointerActive = false

    init(layout: WheelLayout, favorites: [CGWindowID: pid_t] = [:]) {
        self.layout = layout
        self.favorites = favorites
    }

    /// Regular apps (the ones with a Dock icon), in launch order — stable slots for muscle memory.
    /// Sorted explicitly: Apple documents the order of `runningApplications` as unspecified.
    /// `leaving`: apps on their way out that are still running.
    func reload(pointer: CGPoint, quickSwitchTo quickSwitchPID: pid_t?, window quickSwitchWindowID: CGWindowID?,
                leaving: Set<pid_t> = [], favoritesOnly: Bool = false) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !leaving.contains($0.processIdentifier) }
            .map { (app: $0, started: $0.startDate) } // look the date up once, not per comparison
            .sorted { ($0.started, $0.app.processIdentifier) < ($1.started, $1.app.processIdentifier) }
            .map { WheelItem(app: $0.app) }
        let windows = WindowList.windowsByApp(of: Set(apps.map(\.pid)))
        load(apps: apps, windows: windows, pointer: pointer, quickSwitchTo: quickSwitchPID, window: quickSwitchWindowID,
             favoritesOnly: favoritesOnly)
    }

    /// `reload` once the running apps (in slot order) and their windows are known.
    /// Tests start here.
    func load(apps: [WheelItem], windows: [pid_t: [AppWindow]], pointer: CGPoint,
              quickSwitchTo quickSwitchPID: pid_t?, window quickSwitchWindowID: CGWindowID? = nil,
              favoritesOnly: Bool = false) {
        self.quickSwitchPID = quickSwitchPID
        self.quickSwitchWindowID = quickSwitchWindowID
        wasTouched = false
        hasClosedSomething = false
        let running = Set(apps.map(\.pid))
        allApps = apps
        allWindows = windows.filter { running.contains($0.key) }
        quittingPIDs.formIntersection(running)
        closingWindows = closingWindows.filter { running.contains($0.value) }
        showsFavorites = favoritesOnly
        favoritesOnWheel = favorites
        select(nil)
        showSectors()
        // No favorites to show: everything, rather than an empty wheel.
        if showsFavorites, items.isEmpty {
            showsFavorites = false
            showSectors()
        }
        // Drop screenshots of windows that are gone and apps that have quit.
        let windowIDs = Set(allWindows.values.flatMap { $0.map(\.id) })
        previews = previews.filter { key, _ in
            switch key {
            case .window(let id): windowIDs.contains(id)
            case .app(let pid): running.contains(pid)
            }
        }
        anchorPointer(at: pointer)
        updateHover(at: pointer)
    }

    /// `windows` and `items` from every app and window: all of them, or only the favorites.
    /// In favorites a hidden app stands for its favorite windows: they aren't listed while
    /// it's hidden, and switching to it shows them again.
    private func showSectors() {
        let allSectorCount = allApps.reduce(0) { $0 + max(1, allWindows[$1.pid]?.count ?? 0) }
        iconSize = layout.iconSize(count: allSectorCount)
        let favoriteApps = Set(favoritesOnWheel.values)
        var shown: [pid_t: [AppWindow]] = [:]
        for (pid, appWindows) in allWindows {
            let appShown = showsFavorites ? appWindows.filter { favoritesOnWheel[$0.id] == pid } : appWindows
            if !appShown.isEmpty { shown[pid] = appShown }
        }
        windows = shown
        items = sectors(for: showsFavorites
            ? allApps.filter { shown[$0.pid] != nil || ($0.isHidden && favoriteApps.contains($0.pid)) }
            : allApps)
    }

    /// One sector per app — or one per window of an app that has several.
    private func sectors(for apps: [WheelItem]) -> [WheelItem] {
        apps.flatMap { item in
            let appWindows = windows[item.pid] ?? []
            guard appWindows.count > 1 else { return [item] }
            // Creation order (window IDs only grow), not front to back: that changes with every
            // switch, and the sectors would swap places under the cursor.
            return appWindows.sorted { $0.id < $1.id }.enumerated().map { number, window in
                var sector = item
                sector.window = window
                sector.windowNumber = number + 1
                return sector
            }
        }
    }

    /// Show activity before removing the window or doing any asynchronous checks.
    func beginClosingWindow(_ id: CGWindowID, of pid: pid_t) {
        closingWindows[id] = pid
        removeWindow(id, of: pid)
    }

    func finishClosingWindow(_ id: CGWindowID) {
        closingWindows[id] = nil
    }

    /// Window close requests not yet handed over to quitting or finished.
    private var closingWindows: [CGWindowID: pid_t] = [:]

    /// A window was closed from the wheel: take it off right away instead of waiting for the app.
    /// (If the app keeps it open after all, say to ask about unsaved changes, it's back next time.)
    func removeWindow(_ id: CGWindowID, of pid: pid_t) {
        allWindows[pid]?.removeAll { $0.id == id }
        previews[.window(id)] = nil
        touch() // releasing ⌘ now must not count as a quick ⌘Tab
        hasClosedSomething = true
        rebuildSectors()
    }

    /// Apps told to quit that haven't yet: their icons show it. Kept across openings until
    /// the app has quit or turned out to stay.
    private(set) var quittingPIDs: Set<pid_t> = []

    func setQuitting(_ pid: pid_t, _ isQuitting: Bool) {
        if isQuitting {
            quittingPIDs.insert(pid)
            closingWindows = closingWindows.filter { $0.value != pid }
        } else {
            quittingPIDs.remove(pid)
        }
    }

    /// ⌘Q was sent. The sectors go only once the app has quit (`removeApp`).
    func noteQuitRequested() {
        touch()
        hasClosedSomething = true
    }

    /// An app quit while the wheel is open (⌘Q here, or on its own): its sectors go.
    func removeApp(_ pid: pid_t) {
        quittingPIDs.remove(pid)
        closingWindows = closingWindows.filter { $0.value != pid }
        guard allApps.contains(where: { $0.pid == pid }) else { return }
        let gone = Set((allWindows[pid] ?? []).map(\.id))
        allApps.removeAll { $0.pid == pid }
        allWindows[pid] = nil
        previews = previews.filter { key, _ in
            switch key {
            case .window(let id): !gone.contains(id)
            case .app(let app): app != pid
            }
        }
        rebuildSectors()
    }

    /// Sectors again after a window or an app went away. Indices shift with them, so the
    /// selection is placed anew: under the pointer when the mouse drives it; else on the same
    /// app (Tab to it, then ⌘W ⌘W ⌘W closes its windows one by one); else on whatever slid
    /// into its place.
    private func rebuildSectors() {
        let previous = selectedIndex.map { (index: $0, pid: items[$0].pid) }
        // Re-placing the selection below is our doing, not a pick by the user.
        let closedSomething = hasClosedSomething
        defer { hasClosedSomething = closedSomething }
        select(nil) // before `items` changes: the old index may not exist any more
        showSectors()

        if isPointerActive {
            // Removing the last window must not lose a busy rail under the cursor, even
            // when its end lies across the neighboring sector's angular boundary.
            let owner = previous.flatMap { previous -> Int? in
                if previous.index < items.count, items[previous.index].pid == previous.pid {
                    return previous.index
                }
                return items.firstIndex { $0.pid == previous.pid }
            }
            if let owner, isActionRailBusy(for: items[owner]), railContains(lastPointer, index: owner) {
                select(owner)
            }
            movePointer(to: lastPointer)
            return
        }
        updateHover(at: lastPointer)
        guard let previous, !items.isEmpty else { return }
        if previous.index < items.count, items[previous.index].pid == previous.pid {
            select(previous.index)
        } else if let sameApp = items.firstIndex(where: { $0.pid == previous.pid }) {
            select(sameApp)
        } else {
            select(min(previous.index, items.count - 1))
        }
    }

    /// nil removes the preview (nothing to show any more).
    func setPreview(_ image: CGImage?, for key: PreviewKey) {
        previews[key] = image.map { NSImage(cgImage: $0, size: .zero) }
    }

    /// The window switching to `item` brings up; nil when the app has none to show.
    func chosenWindow(of item: WheelItem) -> AppWindow? {
        item.window ?? windows[item.pid]?.first
    }

    /// The chosen window, if the wheel can close it (the close action, ⌘W). Not a window on
    /// another desktop: Accessibility, which presses its close button, only sees the shown ones.
    func closableWindow(of item: WheelItem) -> AppWindow? {
        guard let window = chosenWindow(of: item) else { return nil }
        if case .otherDesktop = window.place { return nil }
        return window
    }

    /// Keep the rail throughout the close request, including the handoff to quitting.
    func showsActionRail(for item: WheelItem) -> Bool {
        isActionRailBusy(for: item) || chosenWindow(of: item) != nil
    }

    /// A button on the selected sector's rail.
    enum RailButton: Hashable {
        case close
        case favorite
    }

    /// The rail's buttons, from the selection mark outward: × where it can close the window,
    /// then ★ for any window. None while the rail shows progress.
    func railButtons(for item: WheelItem) -> [RailButton] {
        guard !isActionRailBusy(for: item), chosenWindow(of: item) != nil else { return [] }
        return closableWindow(of: item) == nil ? [.favorite] : [.close, .favorite]
    }

    /// Whether ★ is lit for the window the sector brings up.
    func isFavorite(_ item: WheelItem) -> Bool {
        chosenWindow(of: item).map { favorites[$0.id] == item.pid } ?? false
    }

    /// ★ on the rail: the window the sector brings up joins the favorites, or leaves them.
    /// It keeps its sector in favorites until the wheel opens again or ⌘Space is pressed.
    func toggleFavorite(_ item: WheelItem) {
        guard let window = chosenWindow(of: item) else { return }
        favorites[window.id] = isFavorite(item) ? nil : item.pid
    }

    /// The app has quit: its windows are gone for good.
    func forgetFavorites(of pid: pid_t) {
        guard favorites.values.contains(pid) else { return }
        favorites = favorites.filter { $0.value != pid }
    }

    /// ⌘Space: every window ⇄ only the favorite ones. When the mouse drives the selection the
    /// pointer picks again; a sector picked with Tab stays picked if its window is still there.
    func toggleFavoritesShown() {
        let previous = selectedItem.map { (pid: $0.pid, window: chosenWindow(of: $0)?.id) }
        let closedSomething = hasClosedSomething
        defer { hasClosedSomething = closedSomething }
        showsFavorites.toggle()
        favoritesOnWheel = favorites
        select(nil)
        showSectors()
        if isPointerActive {
            movePointer(to: lastPointer)
            return
        }
        if let previous {
            select(items.firstIndex { $0.pid == previous.pid && chosenWindow(of: $0)?.id == previous.window })
        }
        updateHover(at: lastPointer)
    }

    func isActionRailBusy(for item: WheelItem) -> Bool {
        if quittingPIDs.contains(item.pid) { return true }
        if let window = chosenWindow(of: item) { return closingWindows[window.id] == item.pid }
        return closingWindows.values.contains(item.pid)
    }

    /// What ⌘W does with a sector.
    enum CloseAction: Equatable {
        /// Close the window (the app's last one quits the app, see the controller).
        case closeWindow(AppWindow)
        /// The app has no window at all: quit it, like ⌘Q. The wheel doesn't show whether an
        /// app has a window, so ⌘W must not depend on it.
        case quitApp
    }

    /// nil: nothing to do. A window on another desktop can't be closed, and quitting would take
    /// it along unseen. A hidden app has windows too, just out of sight. Finder doesn't quit.
    func closeAction(for item: WheelItem) -> CloseAction? {
        guard !isActionRailBusy(for: item) else { return nil }
        if let window = closableWindow(of: item) { return .closeWindow(window) }
        guard chosenWindow(of: item) == nil, !item.isHidden, item.canQuit else { return nil }
        return .quitApp
    }

    /// "Window 2 of 3" for the hub — only for apps with more than one window.
    func windowPosition(of item: WheelItem) -> (index: Int, count: Int)? {
        guard let number = item.windowNumber, let count = windows[item.pid]?.count, count > 1 else { return nil }
        return (number - 1, count)
    }

    /// Picture for the hub: the chosen window, or a stand-in for an app with none on this Space.
    func preview(for item: WheelItem) -> NSImage? {
        if let window = chosenWindow(of: item) {
            return previews[.window(window.id)]
        }
        return previews[.app(item.pid)]
    }

    func movePointer(to point: CGPoint) {
        lastPointer = point
        guard !items.isEmpty else {
            if hoveredRailButton != nil { hoveredRailButton = nil }
            return
        }
        updateHover(at: point)

        if !isPointerActive {
            let moved = hypot(point.x - pointerAnchor.x, point.y - pointerAnchor.y)
            guard moved >= Self.pointerActivationDistance else { return }
            isPointerActive = true
            touch()
        }

        // The segment center→cursor only reaches the sectors once it's longer than the hub.
        // Inside the hub nothing is crossed → nothing is selected, so releasing ⌘ there cancels.
        let distance = hypot(point.x, point.y)
        updateSelectionReach(distance: distance)
        // Keep the visible rail attached to its owner while aiming at its actions,
        // including the short path from the icon. This matters with tightly packed sectors.
        if let index = selectedIndex, showsActionRail(for: items[index]), railContains(point, index: index) {
            return
        }
        guard distance >= layout.innerRadius else {
            select(nil)
            updateHover(at: point)
            return
        }
        let angle = atan2(point.y, point.x)
        let index = WheelGeometry.index(at: angle, count: items.count)
        if index != selectedIndex { hasClosedSomething = false } // picked another sector
        select(index)
        updateHover(at: point)
    }

    /// The app whose sector the segment center→`point` crosses; nil inside the hub.
    /// Used for clicks — no movement threshold, the cursor may already sit on an icon.
    func item(at point: CGPoint) -> WheelItem? {
        let distance = hypot(point.x, point.y)
        guard !items.isEmpty, distance >= layout.innerRadius else { return nil }
        if let index = selectedIndex, showsActionRail(for: items[index]), railContains(point, index: index) {
            return items[index]
        }
        let angle = atan2(point.y, point.x)
        return items[WheelGeometry.index(at: angle, count: items.count)]
    }

    /// Only the buttons on the visible rail are clickable; hidden sectors have none.
    /// Where two hit areas meet, the nearer button wins.
    func railButton(at point: CGPoint) -> RailButton? {
        guard let index = selectedIndex else { return nil }
        let buttons = railButtons(for: items[index])
        return buttons.enumerated()
            .map { slot, button in
                let center = layout.railButtonCenter(slot: slot, index: index, count: items.count, buttons: buttons.count)
                return (button: button, distance: hypot(point.x - center.x, point.y - center.y))
            }
            .filter { $0.distance <= WheelLayout.closeButtonHitRadius }
            .min { $0.distance < $1.distance }?.button
    }

    func closeTarget(at point: CGPoint) -> (item: WheelItem, window: AppWindow)? {
        guard railButton(at: point) == .close, let item = selectedItem,
              let window = closableWindow(of: item) else { return nil }
        return (item, window)
    }

    func favoriteTarget(at point: CGPoint) -> WheelItem? {
        railButton(at: point) == .favorite ? selectedItem : nil
    }

    /// A progress rail is feedback, not a close button or a shortcut into the quitting app.
    func isBusyActionRail(at point: CGPoint) -> Bool {
        guard let index = selectedIndex, isActionRailBusy(for: items[index]) else { return false }
        return railContains(point, index: index)
    }

    /// The rail of sector `index`, as long as its buttons make it.
    private func railContains(_ point: CGPoint, index: Int) -> Bool {
        layout.actionRailContains(point, index: index, count: items.count,
                                  buttons: railButtons(for: items[index]).count)
    }

    // MARK: Rail button hover

    private func updateHover(at point: CGPoint) {
        let hovered = railButton(at: point)
        if hovered != hoveredRailButton { hoveredRailButton = hovered }
    }

    /// Tab / ⇧Tab: next / previous slot clockwise.
    func step(backward: Bool) {
        guard !items.isEmpty else { return }
        let count = items.count
        let current = selectedIndex ?? (backward ? 0 : -1)
        select(((current + (backward ? -1 : 1)) % count + count) % count)
        touch()
        hasClosedSomething = false
        // Keyboard wins until the mouse deliberately moves again.
        anchorPointer(at: lastPointer)
        updateHover(at: lastPointer)
    }

    func reset() {
        select(nil)
        isPointerActive = false
        hasClosedSomething = false
        selectionReach = 0.5
        if hoveredRailButton != nil { hoveredRailButton = nil }
    }

    private func anchorPointer(at point: CGPoint) {
        pointerAnchor = point
        lastPointer = point
        isPointerActive = false
        selectionReach = 0.5
    }

    private func updateSelectionReach(distance: CGFloat) {
        let travel = max(distance - layout.innerRadius, 0)
        // No hard stop at the rim: extra reach keeps adding a little contrast.
        let reach = travel / (travel + max(layout.outerRadius * 0.65, 1))
        // Small visual steps avoid invalidating the view on every subpixel mouse move.
        let rounded = (reach * 100).rounded() / 100
        if selectionReach != rounded { selectionReach = rounded }
    }

    /// Only write on change: every write to an @Observable property triggers a re-render.
    private func select(_ index: Int?) {
        if index != selectedIndex { selectedIndex = index }
    }

    private func touch() {
        if !wasTouched { wasTouched = true }
    }
}

private extension NSRunningApplication {
    /// When the app was launched. `launchDate` is nil for apps LaunchServices didn't start
    /// itself (Finder at login, browsers started by automation tools) — then ask the kernel.
    var startDate: Date {
        if let launchDate { return launchDate }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return .distantPast
        }
        let started = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
    }
}

/// Wheel sizes, shared by drawing (WheelView) and hit-testing (WheelModel).
struct WheelLayout {
    static let standard = WheelLayout(diameter: 560)

    let diameter: CGFloat

    var outerRadius: CGFloat { diameter / 2 - 6 }
    /// The hub: center circle with the window preview and the app name.
    var innerRadius: CGFloat { diameter * 0.34 }
    var iconRadius: CGFloat { (outerRadius + innerRadius) / 2 }
    /// Box for the preview in the hub; with the name below it still fits inside the circle.
    var previewSize: CGSize { CGSize(width: innerRadius * 1.6, height: innerRadius) }

    /// App icons shrink when there are many, so neighbours never touch.
    func iconSize(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let slotLength = 2 * .pi * iconRadius / CGFloat(count)
        return min(60, slotLength * 0.64)
    }

    // MARK: Selected sector action rail

    static let closeButtonSize: CGFloat = 16
    static let closeButtonHitRadius: CGFloat = 11
    /// The rail with one button; additional buttons grow it equally at both ends.
    static let actionRailHalfAngle: Double = 0.085
    static let closeButtonAngleOffset: Double = 0.045
    /// From one rail button to the next.
    static let railButtonSpacing: Double = 0.075
    var actionRailRadius: CGFloat { outerRadius + 4.5 }

    /// The close action stays on the side opposite the icon’s window badge.
    func actionRailDirection(index: Int, count: Int) -> Double {
        let angle = WheelGeometry.angle(of: index, count: count)
        return sin(angle) + cos(angle) >= -0.000_001 ? 1 : -1
    }

    func actionRailAngle(index: Int, count: Int) -> Double {
        WheelGeometry.angle(of: index, count: count)
    }

    /// The close button: the rail's first button, when it has one.
    func closeButtonCenter(index: Int, count: Int, buttons: Int = 2) -> CGPoint {
        railButtonCenter(slot: 0, index: index, count: count, buttons: buttons)
    }

    func railButtonCenter(slot: Int, index: Int, count: Int, buttons: Int = 2) -> CGPoint {
        let offset = Self.closeButtonAngleOffset + Double(slot) * Self.railButtonSpacing - railContentShift(buttons: buttons)
        let angle = WheelGeometry.angle(of: index, count: count) + actionRailDirection(index: index, count: count) * offset
        return CGPoint(x: actionRailRadius * cos(angle), y: actionRailRadius * sin(angle))
    }

    /// Center the whole capsule on the sector, including its buttons and selection mark.
    func actionRailSpan(index: Int, count: Int, buttons: Int) -> (start: Double, end: Double) {
        let half = Self.actionRailHalfAngle + railContentShift(buttons: buttons)
        return (-half, half)
    }

    func railSelectionSpan(index: Int, count: Int, buttons: Int) -> (start: Double, end: Double) {
        let shift = railContentShift(buttons: buttons)
        return actionRailDirection(index: index, count: count) > 0
            ? (-0.065 - shift, -0.005 - shift)
            : (0.005 + shift, 0.065 + shift)
    }

    private func railContentShift(buttons: Int) -> Double {
        Double(max(buttons, 1) - 1) * Self.railButtonSpacing / 2
    }

    /// The visible arc and a narrow approach from its icon to each button keep the selected
    /// owner stable.
    func actionRailContains(_ point: CGPoint, index: Int, count: Int, buttons: Int = 2) -> Bool {
        let angle = WheelGeometry.angle(of: index, count: count)
        let railAngle = actionRailAngle(index: index, count: count)
        let offset = atan2(sin(atan2(point.y, point.x) - railAngle), cos(atan2(point.y, point.x) - railAngle))
        let span = actionRailSpan(index: index, count: count, buttons: buttons)
        if abs(hypot(point.x, point.y) - actionRailRadius) <= Self.closeButtonHitRadius,
           offset >= span.start - 0.035, offset <= span.end + 0.035 { return true }
        let start = CGPoint(x: iconRadius * cos(angle), y: iconRadius * sin(angle))
        return (0..<max(buttons, 1)).contains { slot in
            let end = railButtonCenter(slot: slot, index: index, count: count, buttons: buttons)
            let dx = end.x - start.x, dy = end.y - start.y
            let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)
            guard t >= 0, t <= 1 else { return false }
            return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy) <= Self.closeButtonHitRadius
        }
    }

    /// What the wheel view draws on: the wheel plus room for what sticks out past the rim
    /// (the close action, shadows).
    var canvasSize: CGFloat { diameter + 80 }
}

/// Wheel geometry in SwiftUI coordinates (y down), angles in radians.
/// Slot 0 is at 12 o'clock, then clockwise.
enum WheelGeometry {
    static func sectorAngle(count: Int) -> Double {
        2 * Double.pi / Double(max(count, 1))
    }

    /// Angle of the middle of slot `index`.
    static func angle(of index: Int, count: Int) -> Double {
        -Double.pi / 2 + Double(index) * sectorAngle(count: count)
    }

    /// Which slot an angle (from atan2) points at.
    static func index(at angle: Double, count: Int) -> Int {
        let raw = Int(((angle + Double.pi / 2) / sectorAngle(count: count)).rounded())
        return (raw % count + count) % count
    }
}
