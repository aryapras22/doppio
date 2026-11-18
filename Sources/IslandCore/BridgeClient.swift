import Darwin
import Foundation

public enum BridgeClient {
    /// Best effort: gives up after 200 ms and never throws, because callers are hooks that must not fail.
    public static func send(_ event: BridgeEvent) {
        guard var line = try? JSONEncoder().encode(event) else { return }
        line.append(0x0A)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        guard var addr = try? makeSockAddr(IslandPaths.socket) else { return }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return }
        line.withUnsafeBytes { _ = write(fd, $0.baseAddress, line.count) }
    }
}
