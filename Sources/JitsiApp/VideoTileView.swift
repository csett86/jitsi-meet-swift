import SwiftUI
import AppKit
import WebRTC

/// Renders one WebRTC video track with Metal (`RTCMTLNSVideoView`, the macOS
/// renderer). Tracks arrive and disappear as participants publish or stop their
/// camera, so the view swaps renderers rather than being rebuilt.
struct VideoRendererView: NSViewRepresentable {
    let track: RTCVideoTrack?

    func makeNSView(context: Context) -> RTCMTLNSVideoView {
        let view = RTCMTLNSVideoView()
        context.coordinator.attach(track, to: view)
        return view
    }

    func updateNSView(_ view: RTCMTLNSVideoView, context: Context) {
        context.coordinator.attach(track, to: view)
    }

    static func dismantleNSView(_ view: RTCMTLNSVideoView, coordinator: Coordinator) {
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
                VideoRendererView(track: tile.track)
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
