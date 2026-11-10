import Foundation

// The translator creates an empty marker at composition start and unlinks it at
// commit or cancel. Watch the directory so a short composition can coalesce to idle.
@MainActor
final class CompositionMonitor {
    private let directory: URL
    private let marker: URL
    private let source: DispatchSourceFileSystemObject
    var isComposing: Bool { FileManager.default.fileExists(atPath: marker.path) }

    init(cacheDirectory: URL, changed: @escaping () -> Void) throws {
        directory = cacheDirectory.appendingPathComponent("activity", isDirectory: true)
        marker = directory.appendingPathComponent("composing")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let fd = open(directory.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setCancelHandler { close(fd) }
        reset()
        source.setEventHandler(handler: changed)
        source.resume()
    }

    func reset() { try? FileManager.default.removeItem(at: marker) }

    func stop() {
        source.cancel()
        reset()
        // Only remove an empty directory, never unrelated cache files.
        rmdir(directory.path)
    }
}
