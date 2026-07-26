import Foundation
import SwiftUI
import WebRTC
import JitsiCore
import JitsiMedia

/// One video tile in the grid.
struct Tile: Identifiable {
    /// The mid of the receive section, or `local` for our own camera.
    let id: String
    let endpointID: String
    /// Jitsi source name — what the bridge keys video constraints by.
    var sourceName: String?
    var track: RTCVideoTrack?
    var isLocal: Bool = false

    static let localID = "local"
}

/// Everything the UI observes, and the only place the app talks to `JitsiCore` /
/// `JitsiMedia`. One conference at a time: `join(url:)` builds a fresh
/// `JitsiConference` + `ConferenceCall`, `leave()` tears both down.
///
/// Callbacks from the signaling and media layers arrive on background threads,
/// so every mutation hops to the main actor before touching published state.
@MainActor
final class CallModel: ObservableObject {

    // Join screen
    @Published var conferenceURL = "https://jitsi.luki.org/swiftest"
    @Published var urlError: String?

    // Call state
    @Published private(set) var state: ConferenceState = .idle
    @Published private(set) var iceState = "new"
    @Published private(set) var roomName = ""
    @Published private(set) var participants: [Participant] = []
    @Published private(set) var tiles: [Tile] = []
    @Published private(set) var dominantSpeaker: String?
    @Published private(set) var lastError: String?
    /// Live RTP counters — the difference between "connected" and "media flowing".
    @Published private(set) var stats = MediaStats()

    // Controls
    @Published private(set) var micEnabled = true
    @Published private(set) var cameraEnabled = true

    var isInCall: Bool {
        switch state {
        case .idle, .left, .failed: return false
        default: return true
        }
    }

    private var conference: JitsiConference?
    private var call: ConferenceCall?
    private var localMedia: LocalMediaSource?
    private var factory: PeerConnectionFactory?
    private var tasks: [Task<Void, Never>] = []
    /// Per-tile renderer frame counters (mid → counter).
    private var frameCounters: [String: FrameCounter] = [:]

    /// `open build/JitsiMeetSwift.app --args https://jitsi.luki.org/room --autojoin`
    /// — how the live checks in docs/mac-runbook.md drive the app.
    init() {
        if let url = CommandLine.arguments.first(where: { $0.hasPrefix("http") }) {
            conferenceURL = url
        }
    }

    var autoJoinRequested: Bool { CommandLine.arguments.contains("--autojoin") }

    /// `--leave-after <seconds>`: leave the conference and quit. Makes the whole
    /// app loop (join → media → leave) runnable unattended for the live checks in
    /// docs/mac-runbook.md, and keeps test calls short as
    /// docs/live-testing.md requires.
    var leaveAfter: TimeInterval? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--leave-after"), flag + 1 < arguments.count
        else { return nil }
        return TimeInterval(arguments[flag + 1])
    }

    // MARK: - Join / leave

    func join() {
        guard let parsed = ConferenceURLParser.parse(conferenceURL) else {
            urlError = "That is not a conference URL — try https://jitsi.luki.org/room"
            return
        }
        urlError = nil
        lastError = nil
        roomName = parsed.roomName
        state = .connecting

        Log.write("joining \(parsed.roomName) at \(parsed.config.xmppWebSocketURL)")
        Task {
            // Ask before capturing: a denied camera would otherwise show up as a
            // black tile with no explanation.
            let access = await LocalMediaSource.requestAccess()
            Log.write("device access: camera=\(access.camera) microphone=\(access.microphone)")
            if !access.camera || !access.microphone {
                lastError = "Camera or microphone access was denied in System Settings › Privacy."
            }
            self.start(parsed, camera: access.camera)
        }
    }

    private func start(_ parsed: ParsedConference, camera: Bool) {
        let factory = PeerConnectionFactory()
        let localMedia = LocalMediaSource(factory: factory.factory)
        let conference = JitsiConference(
            transport: URLSessionStanzaTransport(url: parsed.config.xmppWebSocketURL),
            config: parsed.config, roomName: parsed.roomName)
        let call = ConferenceCall(conference: conference, factory: factory, localMedia: localMedia)

        self.factory = factory
        self.localMedia = localMedia
        self.conference = conference
        self.call = call

        if camera { localMedia.startCapture() }
        cameraEnabled = camera
        micEnabled = true
        tiles = [Tile(id: Tile.localID, endpointID: conference.endpointID,
                      track: localMedia.videoTrack, isLocal: true)]

        call.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        call.onRemoteMediaTrack = { [weak self] remote in
            Task { @MainActor in self?.addRemote(remote) }
        }
        call.onRemoteTrackEnded = { [weak self] mid in
            Task { @MainActor in self?.removeTile(mid: mid) }
        }
        call.onIceStateChange = { [weak self] state in
            Log.write("ICE \(Self.describe(state))")
            Task { @MainActor in self?.iceState = Self.describe(state) }
        }
        call.onError = { [weak self] message in
            Log.write("media error: \(message)")
            Task { @MainActor in self?.lastError = message }
        }
        call.onBridgeOpen = { Log.write("colibri bridge channel open") }
        call.onNegotiated = { shape in Log.write("negotiated: \(shape)") }
        // The JVB reports what it is forwarding and why over this channel — the
        // only place to see the bridge's own view of our receive side.
        call.onBridgeMessage = { message in Log.write("bridge <- \(message.prefix(240))") }
        call.onDominantSpeaker = { endpoint in Log.write("dominant speaker: \(endpoint)") }
        call.onSessionTerminated = { [weak self] _ in
            // Routine — e.g. everyone else left. Keep the room, drop the tiles.
            Task { @MainActor in self?.tiles.removeAll { !$0.isLocal } }
        }

        tasks = [Task { await call.run() },
                 Task { await conference.join() },
                 Task { await self.pollStatistics() }]
    }

    /// Poll RTP counters once a second. Also printed, so a headless/live run
    /// leaves evidence that media really flowed (docs/mac-signoff.md).
    private func pollStatistics() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let call else { return }
            let stats: MediaStats = await withCheckedContinuation { continuation in
                call.statistics { continuation.resume(returning: $0) }
            }
            self.stats = stats
            let rendered = frameCounters.values.map(\.summary).sorted().joined(separator: ", ")
            Log.write("media \(stats.summary)" + (rendered.isEmpty ? "" : " · rendered \(rendered)"))
        }
    }

    func leave() {
        let conference = self.conference
        let call = self.call
        localMedia?.stopCapture()
        for task in tasks { task.cancel() }
        tasks = []
        Task {
            await conference?.leave()
            call?.close()
        }
        self.conference = nil
        self.call = nil
        self.localMedia = nil
        self.factory = nil
        tiles = []
        participants = []
        dominantSpeaker = nil
        iceState = "new"
        state = .left
    }

    // MARK: - Controls

    func toggleMic() {
        micEnabled.toggle()
        localMedia?.setAudio(enabled: micEnabled)
        publishMuteState()
    }

    func toggleCamera() {
        cameraEnabled.toggle()
        localMedia?.setVideo(enabled: cameraEnabled)
        publishMuteState()
    }

    /// Jitsi shows mute state from MUC presence, so it has to be published as
    /// well as applied to the local track.
    private func publishMuteState() {
        let conference = self.conference
        let muted = (audio: !micEnabled, video: !cameraEnabled)
        Task { await conference?.setMuted(audio: muted.audio, video: muted.video) }
    }

    // MARK: - Events

    private func handle(_ event: ConferenceEvent) {
        switch event {
        case .stateChanged(let newState):
            state = newState
            Log.write("conference state: \(newState)")
            if case let .failed(reason) = newState { lastError = reason }
        case .roster:
            let conference = self.conference
            Task { @MainActor in
                if let roster = await conference?.roster { self.participants = roster }
            }
        case .dominantSpeaker(let endpoint):
            dominantSpeaker = endpoint
            updateReceiverConstraints()
        default:
            break
        }
    }

    private func addRemote(_ remote: RemoteMediaTrack) {
        // Audio needs no tile: WebRTC plays received audio through the default
        // output device on its own.
        Log.write("remote \(remote.kind) track from \(remote.endpointID) (mid \(remote.mid))")
        guard let video = remote.videoTrack else { return }
        // Count what reaches the render layer, not just what the decoder produced.
        let counter = FrameCounter(label: "\(remote.endpointID) video")
        video.add(counter)
        frameCounters[remote.mid] = counter

        if let index = tiles.firstIndex(where: { $0.id == remote.mid }) {
            tiles[index].track = video
        } else {
            tiles.append(Tile(id: remote.mid, endpointID: remote.endpointID,
                              sourceName: remote.sourceName, track: video))
        }
        updateReceiverConstraints()
    }

    private func removeTile(mid: String) {
        if let counter = frameCounters.removeValue(forKey: mid),
           let track = tiles.first(where: { $0.id == mid })?.track {
            track.remove(counter)
        }
        tiles.removeAll { $0.id == mid }
        updateReceiverConstraints()
    }

    /// Tell the bridge what we are actually showing, so it sends that many
    /// streams at a sensible resolution (`QualityController` decides, the bridge
    /// channel carries it).
    private func updateReceiverConstraints() {
        let remoteTiles = tiles.filter { !$0.isLocal }
        let visible = remoteTiles.compactMap(\.sourceName)
        guard !visible.isEmpty else { return }
        // The dominant speaker's own source goes on stage at full resolution.
        let selected = remoteTiles
            .filter { $0.endpointID == dominantSpeaker }
            .compactMap(\.sourceName)
        let constraints = QualityController.constraints(visibleSources: visible,
                                                        selectedSources: selected,
                                                        bandwidth: .high)
        Log.write("receiver constraints -> \(constraints.colibriMessageJSON())")
        call?.setReceiverConstraints(constraints)
    }

    // MARK: - Display helpers

    func displayName(for tile: Tile) -> String {
        if tile.isLocal { return "You" }
        return participants.first { $0.nick == tile.endpointID }?.nick ?? tile.endpointID
    }

    var statusText: String {
        switch state {
        case .idle: return "Idle"
        case .connecting: return "Connecting…"
        case .authenticating: return "Authenticating…"
        case .joining: return "Joining \(roomName)…"
        case .joined: return "In \(roomName) — ICE \(iceState)"
        case .reconnecting: return "Reconnecting…"
        case .failed(let reason): return "Failed: \(reason)"
        case .left: return "Left the conference"
        }
    }

    private static func describe(_ state: RTCIceConnectionState) -> String {
        switch state {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        default: return "unknown"
        }
    }
}
