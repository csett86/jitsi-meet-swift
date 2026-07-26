import Foundation

/// Minimal logging: stdout plus `~/Library/Logs/JitsiMeetSwift.log`.
///
/// A GUI app launched from Finder has nowhere to print, and the live checks in
/// docs/mac-runbook.md need evidence after the fact — what tracks arrived, what
/// the RTP counters did, what a failed renegotiation said.
enum Log {
    /// `--log <path>` overrides the default, so two instances of the app (a
    /// two-party media check on one machine) do not interleave their logs.
    static let fileURL: URL = {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--log"), flag + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[flag + 1])
        }
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/JitsiMeetSwift.log")
    }()

    private static let queue = DispatchQueue(label: "org.jitsi.swift.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        print(line, terminator: "")
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
