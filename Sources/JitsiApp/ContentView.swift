import SwiftUI
import AppKit

/// The whole app: a join screen, and a call screen once we are in a conference.
struct ContentView: View {
    @StateObject private var model = CallModel()

    var body: some View {
        Group {
            if model.isInCall {
                CallView(model: model)
            } else {
                JoinView(model: model)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .task {
            guard model.autoJoinRequested else { return }
            model.join()
            if let snapshot = WindowSnapshot.requested {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(snapshot.delay * 1_000_000_000))
                    WindowSnapshot.capture(to: snapshot.path)
                }
            }
            if let seconds = model.leaveAfter {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                model.leave()
                try? await Task.sleep(nanoseconds: 1_000_000_000)   // let the leave presence go out
                NSApp.terminate(nil)
            }
        }
    }
}

/// The single user-facing input of the whole client: a conference URL.
struct JoinView: View {
    @ObservedObject var model: CallModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Jitsi Meet — Swift")
                .font(.largeTitle.weight(.semibold))
            Text("Paste a conference URL. Everything else — XMPP host, MUC domain, "
                 + "focus — is derived from it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            HStack {
                TextField("https://jitsi.luki.org/room", text: $model.conferenceURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(model.join)
                Button("Join", action: model.join)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 520)

            if let error = model.urlError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if let error = model.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.statusText).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(30)
    }
}

/// The call: an adaptive tile grid plus the mic / camera / leave controls.
struct CallView: View {
    @ObservedObject var model: CallModel

    private var columns: [GridItem] {
        let count = max(1, min(3, Int(Double(model.tiles.count).squareRoot().rounded(.up))))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.tiles) { tile in
                        VideoTileView(tile: tile,
                                      name: model.displayName(for: tile),
                                      isDominant: model.dominantSpeaker == tile.endpointID)
                    }
                }
                .padding(12)
            }
            Divider()
            controls
        }
    }

    /// Roster size plus the live RTP counters — kept out of the view builder,
    /// which cannot type-check string concatenation of this size.
    private var subtitle: String {
        let count = model.participants.count
        let people = "\(count) participant" + (count == 1 ? "" : "s")
        return people + " · " + model.stats.summary
    }

    private var controls: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusText).font(.callout)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            Spacer()
            Button(action: model.toggleMic) {
                Label(model.micEnabled ? "Mute" : "Unmute",
                      systemImage: model.micEnabled ? "mic.fill" : "mic.slash.fill")
            }
            Button(action: model.toggleCamera) {
                Label(model.cameraEnabled ? "Stop video" : "Start video",
                      systemImage: model.cameraEnabled ? "video.fill" : "video.slash.fill")
            }
            Button(role: .destructive, action: model.leave) {
                Label("Leave", systemImage: "phone.down.fill")
            }
            .keyboardShortcut("w", modifiers: .command)
        }
        .padding(12)
    }
}
