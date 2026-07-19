import Foundation
import XCTest

/// One captured WebSocket frame, matching the committed `docs/fixtures/*.json`
/// shape: `[{direction, timestamp, payload}]`.
struct CapturedFrame: Codable {
    let direction: String   // "in" or "out"
    let timestamp: Double
    let payload: String
}

/// Loads committed fixtures from `docs/fixtures/`. Tests read the canonical
/// committed captures directly (located relative to this source file) rather
/// than duplicating them as bundled resources, so there is a single source of
/// truth for captured traffic.
enum Fixtures {
    static var directory: URL {
        // .../Tests/JitsiCoreTests/FixtureLoader.swift -> repo root -> docs/fixtures
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // JitsiCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("docs/fixtures", isDirectory: true)
    }

    static func frames(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> [CapturedFrame] {
        let url = directory.appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([CapturedFrame].self, from: data)
    }

    /// Convenience: just the payload strings, optionally filtered by direction.
    static func payloads(_ name: String, direction: String? = nil) throws -> [String] {
        try frames(name)
            .filter { direction == nil || $0.direction == direction }
            .map(\.payload)
    }
}
