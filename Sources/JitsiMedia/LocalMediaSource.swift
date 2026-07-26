#if os(macOS)
import Foundation
import AVFoundation
import WebRTC

/// Captures the local camera and microphone via AVFoundation and exposes them as
/// WebRTC tracks. [MAC] — needs camera/mic hardware, so it is written here but
/// verified by a human (docs/mac-signoff.md). The app bundle's Info.plist must
/// declare `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`, or
/// macOS kills the process the moment capture starts (see Tools/mac-app).
///
/// The microphone is not captured here: WebRTC's own audio device module opens
/// the default input as soon as an audio track is attached to a peer connection.
/// `setAudio(enabled:)` is therefore the mute control, and the OS-level device
/// choice stays with the system's default input.
public final class LocalMediaSource {
    /// The media-stream id our tracks are published under. Jitsi does not key
    /// anything off it (ownership is signaled per source name), but WebRTC wants
    /// both tracks in one stream so they are treated as one participant.
    public static let streamID = "jitsi-local"

    private let factory: RTCPeerConnectionFactory

    public let audioTrack: RTCAudioTrack
    public let videoTrack: RTCVideoTrack
    private let videoSource: RTCVideoSource
    private let capturer: RTCCameraVideoCapturer
    private var capturing = false

    public init(factory: RTCPeerConnectionFactory) {
        self.factory = factory

        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        self.audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")

        let videoSource = factory.videoSource()
        self.videoSource = videoSource
        self.capturer = RTCCameraVideoCapturer(delegate: videoSource)
        self.videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
    }

    /// Cameras the system offers, in the order AVFoundation reports them.
    public static var cameras: [AVCaptureDevice] { RTCCameraVideoCapturer.captureDevices() }

    /// Ask for camera and microphone access. macOS only prompts once per app;
    /// afterwards this returns the standing decision. Capture without it yields a
    /// black frame and a silent track, so callers should surface a refusal.
    public static func requestAccess() async -> (camera: Bool, microphone: Bool) {
        async let camera = withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
        }
        async let microphone = withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
        }
        return await (camera, microphone)
    }

    /// Start capturing from `device` (the first camera by default) at up to 720p.
    /// Idempotent — starting an already-running capture is a no-op.
    @discardableResult
    public func startCapture(device: AVCaptureDevice? = nil, fps: Int = 30) -> Bool {
        guard !capturing else { return true }
        guard let device = device ?? Self.cameras.first,
              let format = Self.bestFormat(for: device) else { return false }
        capturing = true
        capturer.startCapture(with: device, format: format, fps: fps)
        return true
    }

    public func stopCapture() {
        guard capturing else { return }
        capturing = false
        capturer.stopCapture()
    }

    /// Mute/unmute. Disabling a track keeps the transceiver and the negotiated
    /// session intact and simply stops the media — which is what Jitsi's mute is
    /// (the other side is told via presence, see `JitsiConference.setMuted`).
    public func setAudio(enabled: Bool) { audioTrack.isEnabled = enabled }

    /// Video mute also stops the camera, so the capture light goes out rather
    /// than the app quietly holding the camera open while "muted".
    public func setVideo(enabled: Bool) {
        videoTrack.isEnabled = enabled
        if enabled { startCapture() } else { stopCapture() }
    }

    /// Pick the format with the largest area not exceeding 720p height.
    private static func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        return formats.max { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            func score(_ d: CMVideoDimensions) -> Int32 {
                d.height <= 720 ? d.width * d.height : 0
            }
            return score(l) < score(r)
        }
    }
}
#endif
