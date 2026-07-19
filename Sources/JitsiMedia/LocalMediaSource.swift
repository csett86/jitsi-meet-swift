#if os(macOS)
import Foundation
import AVFoundation
import WebRTC

/// Captures the local camera and microphone via AVFoundation and exposes them as
/// WebRTC tracks. [MAC] — needs camera/mic hardware, so it is written here but
/// verified by a human (docs/mac-signoff.md). The app's Info.plist must declare
/// `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`.
public final class LocalMediaSource {
    private let factory: RTCPeerConnectionFactory

    public let audioTrack: RTCAudioTrack
    public let videoTrack: RTCVideoTrack
    private let videoSource: RTCVideoSource
    private let capturer: RTCCameraVideoCapturer

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

    /// Start capturing from the first available camera at a reasonable format.
    public func startCapture(fps: Int = 30) {
        guard let device = RTCCameraVideoCapturer.captureDevices().first,
              let format = bestFormat(for: device) else { return }
        capturer.startCapture(with: device, format: format, fps: fps)
    }

    public func stopCapture() {
        capturer.stopCapture()
    }

    public func setAudio(enabled: Bool) { audioTrack.isEnabled = enabled }
    public func setVideo(enabled: Bool) { videoTrack.isEnabled = enabled }

    /// Pick the format with the largest area not exceeding 720p height.
    private func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
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
