// main.swift — SignalingSpike entry point.
//
// USAGE:
//   swift run SignalingSpike [--json] [domain] [room] [nick]
//
// DEFAULTS:
//   domain  = alpha.jitsi.net
//   room    = testroom@conference.alpha.jitsi.net
//   nick    = spike
//
// EXAMPLE:
//   swift run SignalingSpike --json alpha.jitsi.net testroom@conference.alpha.jitsi.net spike
//
// PURPOSE (Phase 0 definition of done):
//   Connect to alpha.jitsi.net via XMPP-over-WebSocket (RFC 7395), authenticate with
//   SASL ANONYMOUS, join the MUC room, and print the raw session-initiate stanza from
//   Jicofo to stdout. Run this against a live call and diff the output against
//   Packages/JitsiSignaling/Tests/JitsiSignalingTests/Fixtures/alphajitsi-join.json
//   to validate the fixture shapes.

import Foundation

let rawArgs = CommandLine.arguments.dropFirst()
let emitJSON = rawArgs.contains("--json")
let positionalArgs = rawArgs.filter { $0 != "--json" }

let domain = positionalArgs.count > 0 ? positionalArgs[0] : "alpha.jitsi.net"
let room   = positionalArgs.count > 1 ? positionalArgs[1] : "testroom@conference.\(domain)"
let nick   = positionalArgs.count > 2 ? positionalArgs[2] : "spike"

print("SignalingSpike — Phase 0 XMPP feasibility tool")
print("Domain : \(domain)")
print("Room   : \(room)")
print("Nick   : \(nick)")
print(String(repeating: "-", count: 60))

let client = XMPPClient(domain: domain, room: room, nick: nick, emitJSON: emitJSON)
client.run()
