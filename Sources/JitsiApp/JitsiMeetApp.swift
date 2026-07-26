import SwiftUI
import AppKit

/// [MAC] The macOS client (Phase 4). Deliberately small: the join flow, a tile
/// grid, and mic/camera/leave. All conference logic lives in `JitsiCore`
/// (pure, Linux-tested) and `JitsiMedia` (WebRTC).
///
/// Run it from a bundle built by `Tools/mac-app/make-app.sh` — an unbundled
/// binary has no Info.plist, so macOS refuses camera and microphone access.
@main
struct JitsiMeetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Jitsi Meet — Swift") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM-built app is launched without the usual Finder activation, so
        // bring the window forward ourselves.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
