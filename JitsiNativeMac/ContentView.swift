import SwiftUI

struct ContentView: View {
    @State private var urlString = ""
    @State private var config: BackendConfig?
    @State private var parseError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Jitsi Meet")
                .font(.largeTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                TextField(
                    "Conference URL (e.g. https://alpha.jitsi.net/MyRoom)",
                    text: $urlString
                )
                .textFieldStyle(.roundedBorder)

                Button("Join") {
                    attemptJoin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error = parseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if let config {
                connectionDetails(config)
            }

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 580, minHeight: 280)
    }

    // MARK: - Private

    private func attemptJoin() {
        parseError = nil
        config = nil
        do {
            config = try BackendConfig(conferenceURL: urlString.trimmingCharacters(in: .whitespaces))
        } catch {
            parseError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func connectionDetails(_ c: BackendConfig) -> some View {
        GroupBox("Parsed Connection Details") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                detailRow("Room", c.displayName)
                detailRow("XMPP WebSocket", c.xmppWebSocketURL.absoluteString)
                detailRow("XMPP Domain", c.xmppDomain)
                detailRow("MUC Domain", c.mucDomain)
                detailRow("Conference JID", c.conferenceJID)
                detailRow("Focus JID", c.focusUserJID)
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .gridColumnAlignment(.leading)
        }
    }
}

#Preview {
    ContentView()
}
