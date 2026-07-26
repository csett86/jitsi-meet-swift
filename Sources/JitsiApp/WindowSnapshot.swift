import AppKit

/// Writes a PNG of the app's own window.
///
/// Metal-rendered video does not show up in AppKit's view-drawing APIs
/// (`cacheDisplay`, `dataWithPDF`), so checking that video actually reaches the
/// screen — and in the right orientation — otherwise needs a human with eyes on
/// the window. Capturing our *own* window needs no screen-recording permission,
/// which keeps the `[MAC]` checks in docs/mac-runbook.md self-verifying.
///
///     open -n build/JitsiMeetSwift.app --args <url> --autojoin \
///       --snapshot /tmp/app.png --snapshot-after 12
enum WindowSnapshot {

    /// `--snapshot <path>`, with an optional `--snapshot-after <seconds>`
    /// (default 10 — long enough for a call to be up and rendering).
    static var requested: (path: String, delay: TimeInterval)? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count
        else { return nil }
        let delay = arguments.firstIndex(of: "--snapshot-after")
            .flatMap { $0 + 1 < arguments.count ? TimeInterval(arguments[$0 + 1]) : nil } ?? 10
        return (arguments[flag + 1], delay)
    }

    @MainActor
    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else {
            return Log.write("snapshot: no visible window")
        }
        guard let image = CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]) else {
            return Log.write("snapshot: the window server returned no image")
        }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        guard let png else { return Log.write("snapshot: could not encode PNG") }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            Log.write("snapshot: wrote \(image.width)x\(image.height) to \(path)")
        } catch {
            Log.write("snapshot: \(error.localizedDescription)")
        }
    }
}
