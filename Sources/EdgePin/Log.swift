import Foundation

/// Launched from Finder there is no terminal, so keep a log to look at when
/// something misbehaves: ~/Library/Logs/edgepin.log.
private let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/edgepin.log")
private let stamp = ISO8601DateFormatter()

func log(_ message: String) {
    let line = Data("\(stamp.string(from: Date())) \(message)\n".utf8)
    FileHandle.standardError.write(line)
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        h.write(line)
        try? h.close()
    } else {
        try? line.write(to: logURL)
    }
}
