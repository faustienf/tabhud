import AppKit
import ApplicationServices
import ServiceManagement

/// What the app needs from macOS. All checks are cheap and live, so the setup window
/// can poll them and flip a row to "granted" while the user is still in System Settings.
@MainActor
enum Permissions {
    /// Required: the ⌘Tab event tap and raising other apps' windows.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Optional: window previews in the hub. Without it the hub shows app icons.
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Puts the app into the Accessibility list (switched off; macOS shows its own alert)
    /// and opens that list, so the user only has to flip the switch.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacySettings("Privacy_Accessibility")
    }

    /// The system prompt shows only the very first time; afterwards the list in
    /// System Settings is the only way, so open it as well.
    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        openPrivacySettings("Privacy_ScreenCapture")
    }

    private static func openPrivacySettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// "Open at login" through the system Login Items list (System Settings → General → Login Items).
@MainActor
enum LoginItem {
    /// Where the app was when it was last added.
    private static let pathKey = "loginItemPath"

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(Bundle.main.bundlePath, forKey: pathKey)
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Login Items remember where the app was when it was added. Somewhere else now (an update
    /// renamed CmdTabWheel.app to ⌘Tab HUD.app, or it was dragged to another folder), it's
    /// added again from here, or the next login would look for it where it no longer is.
    static func followMove() {
        #if !DEBUG // a debug build in build/ mustn't take the installed copy's place
        guard status == .enabled,
              UserDefaults.standard.string(forKey: pathKey) != Bundle.main.bundlePath
        else { return }
        log.notice("re-adding the login item from the app's new place")
        try? setEnabled(false)
        try? setEnabled(true)
        #endif
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
