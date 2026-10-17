import Foundation
import Vapor

/// A Cloudflare quick tunnel: a public https address for this server, with no
/// account, for app connections and provider callbacks across networks. It runs `cloudflared` alongside the
/// server. The address changes every time the server starts.
final class QuickTunnel: @unchecked Sendable {
    let url: String
    private let process: Process

    private init(url: String, process: Process) {
        self.url = url
        self.process = process
    }

    /// Where cloudflared is installed, or nil. `RIPPLE_CLOUDFLARED` overrides.
    /// Apps run from Xcode don't get Homebrew's PATH, so the usual places are checked directly.
    static func cloudflaredPath(env: [String: String]) -> String? {
        let candidates = [env["RIPPLE_CLOUDFLARED"], "/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared", "/usr/bin/cloudflared"]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Starts cloudflared pointing at this server and waits for the address it prints.
    static func start(executable: String, port: Int, timeout: TimeInterval = 30) async throws -> QuickTunnel {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["tunnel", "--no-autoupdate", "--url", "http://localhost:\(port)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let log = TunnelLog()
        // Keeps draining cloudflared's output for as long as it runs, so it never blocks on a full pipe.
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                log.add(String(decoding: data, as: UTF8.self))
            }
        }
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let url = log.address {
                return QuickTunnel(url: url, process: process)
            }
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        if process.isRunning { process.terminate() }
        throw Abort(.internalServerError, reason: "cloudflared printed no address. Its output: \(log.text.suffix(600))")
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    /// The quick tunnel address in cloudflared's output, if it has appeared.
    /// Its log also mentions api.trycloudflare.com, which isn't the address.
    static func address(in text: String) -> String? {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#, options: .regularExpression, range: searchRange) {
            let match = String(text[range])
            if match != "https://api.trycloudflare.com" { return match }
            searchRange = range.upperBound..<text.endIndex
        }
        return nil
    }
}

/// cloudflared's output so far. Written on a background queue, read while waiting.
private final class TunnelLog: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var found: String?

    func add(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        guard found == nil else { return }
        buffer += chunk
        found = QuickTunnel.address(in: buffer)
    }

    var address: String? {
        lock.lock()
        defer { lock.unlock() }
        return found
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

/// Stops cloudflared when the server shuts down.
struct TunnelLifecycle: LifecycleHandler {
    let tunnel: QuickTunnel

    func shutdown(_ application: Application) {
        tunnel.stop()
    }
}
