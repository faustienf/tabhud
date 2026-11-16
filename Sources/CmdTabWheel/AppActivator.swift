import AppKit
import ApplicationServices

/// Brings another app to the front.
///
/// Why not just `NSRunningApplication.activate()`: since macOS 14 activation is "cooperative" —
/// the system may ignore the request when the caller isn't the active app, and our agent never is.
/// So:
/// 1. A window to bring up (on screen, on another desktop or minimized) → focus and raise it the
///    way AltTab and yabai do: private SkyLight calls make the app frontmost and the window key;
///    Accessibility un-minimizes and raises it. A window on another desktop or in full screen
///    needs its Space shown first: those calls don't switch there.
/// 2. No window (the app is hidden, or has none) or step 1 didn't take →
///    open the app through LaunchServices, exactly like clicking its Dock icon.
@MainActor
enum AppActivator {
    /// `windowID`: the window to bring up; nil = the app's front window.
    /// `opensWindowIfNone`: for an app with no window here, do what a Dock click does (which
    /// opens a new window if it has none at all). Off when only handing focus back: an app the
    /// user just closed the windows of must not get a fresh one.
    static func activate(pid: pid_t, windowID requestedWindowID: CGWindowID? = nil, opensWindowIfNone: Bool = true) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        let name = app.localizedName ?? "pid \(pid)"

        guard let windowID = requestedWindowID ?? WindowList.topmostWindowID(of: pid) else {
            guard opensWindowIfNone else {
                log.notice("activating \(name, privacy: .public), no window to bring up")
                app.activate()
                return
            }
            log.notice("activating \(name, privacy: .public) via LaunchServices")
            openViaLaunchServices(app)
            return
        }

        Task {
            // Accessibility calls go to the target app and block while it's busy. Keep them off
            // the main thread — it also runs our keyboard tap, and a stall there freezes typing.
            let focused = await Task.detached(priority: .userInitiated) {
                await WindowFocus.focusAndRaise(pid: pid, windowID: windowID)
            }.value

            // Check that it actually worked; if not, fall back to the Dock-click way.
            if focused { try? await Task.sleep(for: .milliseconds(250)) }
            if focused, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                if WindowList.isOnScreen(windowID) {
                    log.notice("activated \(name, privacy: .public) via SkyLight + AXRaise")
                } else {
                    // LaunchServices wouldn't switch Spaces either.
                    log.error("activated \(name, privacy: .public), but its window stayed on another desktop")
                }
            } else {
                log.notice("SkyLight didn't activate \(name, privacy: .public) → LaunchServices")
                openViaLaunchServices(app)
            }
        }
    }

    /// Same as clicking the Dock icon: switches Space, unhides, un-minimizes or
    /// opens a new window if the app has none.
    private static func openViaLaunchServices(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            app.activate(options: [.activateAllWindows])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                log.error("LaunchServices open failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Window focusing through private SkyLight (WindowServer) calls plus Accessibility,
/// looked up at runtime. Signatures and the magic event record come from yabai / AltTab.
/// Not tied to the main actor: safe to call from a background thread.
private enum WindowFocus {
    private typealias GetProcessForPID =
        @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessWithOptions =
        @convention(c) (UnsafePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError.RawValue
    private typealias PostEventRecordTo =
        @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafePointer<UInt8>) -> CGError.RawValue

    // GetProcessForPID is public but deprecated — looked up dynamically to avoid the warning.
    private static let getProcessForPID: GetProcessForPID? = symbol("GetProcessForPID")
    private static let setFrontProcessWithOptions: SetFrontProcessWithOptions? = symbol("_SLPSSetFrontProcessWithOptions")
    private static let postEventRecordTo: PostEventRecordTo? = symbol("SLPSPostEventRecordTo")
    private typealias GetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>) -> CGError.RawValue
    private static let getFrontProcess: GetFrontProcess? = symbol("_SLPSGetFrontProcess")

    /// kCPSUserGenerated: treat it as if the user clicked the window.
    private static let userGenerated: UInt32 = 0x200

    static func focusAndRaise(pid: pid_t, windowID: CGWindowID) async -> Bool {
        guard let getProcessForPID, setFrontProcessWithOptions != nil, postEventRecordTo != nil else {
            log.error("SkyLight symbols not found")
            return false
        }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }

        // A minimized window comes out of the Dock first.
        var window = AXWindow.find(pid: pid, windowID: windowID, expected: false)
        if let window, AXWindow.unminimize(window) {
            log.notice("un-minimized the window")
        }
        // A window on another desktop or in full screen: go to its Space first. Making the app
        // frontmost with that window doesn't switch Spaces (not out of a full-screen one).
        if window == nil, !WindowList.isOnScreen(windowID) {
            window = await showSpace(of: windowID, pid: pid, psn: &psn)
        }

        // 1. Make the app frontmost — this alone does NOT bring its window above other apps' windows.
        guard front(&psn, windowID: windowID) else { return false }
        // 2. Make the window key (focused for keyboard).
        makeKey(&psn, windowID: windowID)
        // 3. Physically raise the window to the top.
        if let window {
            raise(window)
        } else {
            log.error("AX: window \(windowID, privacy: .public) isn't there to raise")
        }
        return true
    }

    /// Switches to the Space with the window: on another desktop, or a full-screen one.
    /// Returns the window's Accessibility element for raising it, if it could be found.
    private static func showSpace(of windowID: CGWindowID, pid: pid_t,
                                  psn: inout ProcessSerialNumber) async -> AXUIElement? {
        // An app with no windows on the shown desktops: made frontmost without a particular
        // window, the Dock takes the user to a Space with its windows, like the system ⌘Tab.
        if WindowList.onScreenWindowsByApp()[pid]?.isEmpty ?? true {
            log.notice("the window is on another desktop: switching to its app's")
            _ = front(&psn, windowID: 0)
            if await waitUntilOnScreen(windowID) {
                return await elementOnceShown(pid: pid, windowID: windowID)
            }
        }
        // The app has windows here too (or the Dock picked another of its desktops), so the Dock
        // stays put. Raising the window itself through Accessibility switches there (AltTab's
        // way), but only while its app is frontmost: with another app in front it does nothing.
        guard let element = AXWindow.findOnAnyDesktop(pid: pid, windowID: windowID) else {
            log.error("couldn't switch to the desktop of window \(windowID, privacy: .public)")
            return nil
        }
        log.notice("the window is on another desktop: raising it there")
        _ = front(&psn, windowID: windowID)
        makeKey(&psn, windowID: windowID)
        if !(await waitUntilFrontmost(psn)) {
            log.error("pid \(pid, privacy: .public) didn't come to the front")
        }
        // Once more if the first raise came too early for the app.
        for _ in 0..<2 {
            raise(element)
            if await waitUntilOnScreen(windowID, timeout: .milliseconds(700)) { return element }
        }
        log.error("couldn't switch to the desktop of window \(windowID, privacy: .public)")
        return element
    }

    /// Right after a Space switch the app may not list the window to Accessibility yet.
    private static func elementOnceShown(pid: pid_t, windowID: CGWindowID) async -> AXUIElement? {
        for _ in 0..<5 {
            if let window = AXWindow.find(pid: pid, windowID: windowID, expected: false) { return window }
            try? await Task.sleep(for: .milliseconds(60))
        }
        return AXWindow.findOnAnyDesktop(pid: pid, windowID: windowID)
    }

    /// The Space switch animates; give it time.
    private static func waitUntilOnScreen(_ windowID: CGWindowID,
                                          timeout: Duration = .milliseconds(1500)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if WindowList.isOnScreen(windowID) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return WindowList.isOnScreen(windowID)
    }

    /// Asks WindowServer, not NSWorkspace: that one only learns on the main thread's run loop.
    private static func waitUntilFrontmost(_ psn: ProcessSerialNumber) async -> Bool {
        guard let getFrontProcess else { return false }
        let deadline = ContinuousClock.now + .milliseconds(400)
        while ContinuousClock.now < deadline {
            var front = ProcessSerialNumber()
            if getFrontProcess(&front) == CGError.success.rawValue,
               front.highLongOfPSN == psn.highLongOfPSN, front.lowLongOfPSN == psn.lowLongOfPSN {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// The app frontmost, `windowID` its front window (0: whichever).
    private static func front(_ psn: inout ProcessSerialNumber, windowID: CGWindowID) -> Bool {
        setFrontProcessWithOptions?(&psn, windowID, userGenerated) == CGError.success.rawValue
    }

    /// The window key (focused for keyboard).
    private static func makeKey(_ psn: inout ProcessSerialNumber, windowID: CGWindowID) {
        guard let postEventRecordTo else { return }
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        for index in 0x20..<0x30 { bytes[index] = 0xff }
        bytes[0x08] = 0x01
        _ = postEventRecordTo(&psn, bytes)
        bytes[0x08] = 0x02
        _ = postEventRecordTo(&psn, bytes)
    }

    private static func raise(_ window: AXUIElement) {
        let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if result != .success {
            log.error("AX: raise failed with \(result.rawValue, privacy: .public)")
        }
    }

    private static func symbol<T>(_ name: String) -> T? {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let pointer = dlsym(rtldDefault, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
