// main.swift — SignalingSpike entry point.
//
// USAGE:
//   swift run SignalingSpike [domain] [room] [nick]
//
// DEFAULTS:
//   domain  = alpha.jitsi.net
//   room    = testroom@conference.alpha.jitsi.net
//   nick    = spike
//
// EXAMPLE:
//   swift run SignalingSpike alpha.jitsi.net testroom@conference.alpha.jitsi.net spike
//
// PURPOSE (Phase 0 definition of done):
//   Connect to alpha.jitsi.net via XMPP-over-WebSocket (RFC 7395), authenticate with
//   SASL ANONYMOUS, join the MUC room, and print the raw session-initiate stanza from
//   Jicofo to stdout. Run this against a live call and diff the output against
//   docs/fixtures/alphajitsi-join.json to validate the fixture shapes.

import Foundation

let args = CommandLine.arguments
let domain = args.count > 1 ? args[1] : "alpha.jitsi.net"
let room   = args.count > 2 ? args[2] : "testroom@conference.\(domain)"
let nick   = args.count > 3 ? args[3] : "spike"

print("SignalingSpike — Phase 0 XMPP feasibility tool")
print("Domain : \(domain)")
print("Room   : \(room)")
print("Nick   : \(nick)")
print(String(repeating: "-", count: 60))

let client = XMPPClient(domain: domain, room: room, nick: nick)
client.run()
