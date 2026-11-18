import Foundation

public enum SocketError: Error {
    case pathTooLong
    case syscall(String, Int32)
}

public func makeSockAddr(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw SocketError.pathTooLong }
    withUnsafeMutableBytes(of: &addr.sun_path) { dst in
        for (i, b) in bytes.enumerated() { dst[i] = UInt8(bitPattern: b) }
    }
    return addr
}

/// Accepts connections on a Unix socket and delivers one decoded BridgeEvent per newline-terminated line.
public final class SocketServer: @unchecked Sendable {
    private let path: String
    private let onEvent: @Sendable (BridgeEvent) -> Void
    private var listenFd: Int32 = -1

    public init(path: String = IslandPaths.socket, onEvent: @escaping @Sendable (BridgeEvent) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    public func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.syscall("socket", errno) }
        var addr = try makeSockAddr(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { close(fd); throw SocketError.syscall("bind", errno) }
        guard listen(fd, 32) == 0 else { close(fd); throw SocketError.syscall("listen", errno) }
        listenFd = fd
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { if errno == EINTR { continue } else { return } }
            DispatchQueue.global().async { [self] in read(client) }
        }
    }

    private func read(_ client: Int32) {
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        let decoder = JSONDecoder()
        while true {
            let n = Darwin.read(client, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if let event = try? decoder.decode(BridgeEvent.self, from: line) { onEvent(event) }
            }
        }
    }
}
