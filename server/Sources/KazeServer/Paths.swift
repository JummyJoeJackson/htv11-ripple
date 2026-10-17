import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum ServerPaths {
    /// The `server/` folder, found from this source file's location so that
    /// running from Xcode works without setting a custom working directory.
    static func serverDirectory() -> String {
        let fromSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KazeServer
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // server
        if FileManager.default.fileExists(atPath: fromSource.appendingPathComponent("Public").path) {
            return fromSource.path
        }
        return FileManager.default.currentDirectoryPath
    }
}

enum LANAddress {
    /// The Mac's Wi-Fi IPv4 address, so phones on the same network can reach the server.
    static func ipv4() -> String? {
        #if canImport(Darwin)
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var candidates: [(name: String, ip: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                if status == 0 {
                    let ip = String(cString: host)
                    let name = String(cString: interface.ifa_name)
                    if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                        candidates.append((name, ip))
                    }
                }
            }
            pointer = interface.ifa_next
        }
        return candidates.first(where: { $0.name == "en0" })?.ip ?? candidates.first?.ip
        #else
        return nil
        #endif
    }
}
