import Foundation
import WebRTC

/// Counts frames delivered to a video track's renderers.
///
/// `framesDecoded` in the RTP stats proves the decoder ran; this proves the
/// decoded frames actually reach the rendering layer — the same track object the
/// tile draws. Between them, "remote video is on screen" is checkable without a
/// human squinting at the window (docs/mac-runbook.md, Phase 2 item 3).
final class FrameCounter: NSObject, RTCVideoRenderer {
    private(set) var frames = 0
    private(set) var size: CGSize = .zero
    private let lock = NSLock()
    private let label: String

    init(label: String) {
        self.label = label
        super.init()
    }

    func setSize(_ size: CGSize) {
        lock.lock(); self.size = size; lock.unlock()
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        lock.lock()
        frames += 1
        let count = frames
        let dimensions = "\(frame.width)x\(frame.height)"
        lock.unlock()
        // First frame, then every 5 seconds' worth at 30fps.
        if count == 1 || count % 150 == 0 {
            Log.write("rendered \(count) frame(s) of \(label) at \(dimensions)")
        }
    }

    var summary: String {
        lock.lock(); defer { lock.unlock() }
        return "\(label): \(frames) frames"
    }
}
