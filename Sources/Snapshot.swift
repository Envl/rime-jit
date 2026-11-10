import Foundation

final class Snapshot {
    let url: URL
    private var rows = ""
    private var version = UUID().uuidString
    private var lastWrite = Date.distantPast

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        url = directory.appendingPathComponent("words.tsv")
        clear()
    }

    func replace(_ entries: [Entry]) throws {
        let newRows = entries.map { "\($0.code)\t\($0.word)\n" }.joined()
        if rows != newRows {
            rows = newRows
            version = UUID().uuidString
            lastWrite = .distantPast
        }
        try heartbeat()
    }

    func heartbeat() throws {
        let now = Date()
        guard now.timeIntervalSince(lastWrite) >= 4 else { return }
        let content = "\(Int(now.timeIntervalSince1970) + 12)\t\(version)\n" + rows
        try Data(content.utf8).write(to: url, options: .atomic)
        lastWrite = now
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
        rows = ""
        version = UUID().uuidString
        lastWrite = .distantPast
    }
}
