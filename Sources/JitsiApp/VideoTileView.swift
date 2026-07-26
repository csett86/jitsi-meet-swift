import SwiftUI
import AppKit
import WebRTC

/// `RTCMTLNSVideoView` (the macOS Metal renderer) with an optional horizontal
/// flip, applied to its layer so the Metal content is mirrored by the compositor.
///
/// The flip is recomputed on every layout, and that matters: an AppKit
/// view-backing layer is anchored at `(0, 0)`, not at its centre, so a bare
/// `scaleX: -1` mirrors about the view's **left edge** and pushes the picture
/// entirely out of frame. It needs a translation by the current width — which
/// changes whenever the tile is resized.
final class MirroringVideoView: RTCMTLNSVideoView {
    var mirrored = false {
        didSet {
            guard mirrored != oldValue else { return }
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.setAffineTransform(mirrored
            ? CGAffineTransform(scaleX: -1, y: 1)
                .concatenating(CGAffineTransform(translationX: bounds.width, y: 0))
            : .identity)
    }
}

/// Renders one WebRTC video track with Metal. Tracks arrive and disappear as
/// participants publish or stop their camera, so the view swaps renderers rather
/// than being rebuilt.
struct VideoRendererView: NSViewRepresentable {
    let track: RTCVideoTrack?
    /// Flip horizontally. Used for our own camera: people expect their
    /// self-view to behave like a mirror. This is **display only** — it flips
    /// the layer, not the frames, so what everyone else receives is unchanged
    /// (mirroring the outgoing stream would render text in the room backwards).
    var mirrored: Bool = false

    func makeNSView(context: Context) -> MirroringVideoView {
        let view = MirroringVideoView()
        context.coordinator.attach(track, to: view)
        view.mirrored = mirrored
        return view
    }

    func updateNSView(_ view: MirroringVideoView, context: Context) {
        context.coordinator.attach(track, to: view)
        view.mirrored = mirrored
    }

    static func dismantleNSView(_ view: MirroringVideoView, coordinator: Coordinator) {
        coordinator.detach(from: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the track↔renderer link. A renderer left attached to a track that the
    /// view no longer shows keeps decoding frames into nothing, so every swap
    /// removes the previous one.
    final class Coordinator {
        private var attached: RTCVideoTrack?

        func attach(_ track: RTCVideoTrack?, to view: RTCMTLNSVideoView) {
            guard attached !== track else { return }
            attached?.remove(view)
            attached = track
            track?.add(view)
        }

        func detach(from view: RTCMTLNSVideoView) {
            attached?.remove(view)
            attached = nil
        }
    }
}

/// One participant's tile: their video, their name, and — when they are the
/// dominant speaker — a highlight border.
struct VideoTileView: View {
    let tile: Tile
    let name: String
    let isDominant: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if tile.track != nil {
                // Only our own tile is mirrored — remote video must stay as sent.
                VideoRendererView(track: tile.track, mirrored: tile.isLocal)
            } else {
                Color.black.overlay(
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary))
            }
            Text(name)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.white)
                .padding(8)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDominant ? Color.accentColor : Color.clear, lineWidth: 3))
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
