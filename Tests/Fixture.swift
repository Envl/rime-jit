import AppKit
import Vision

@main
enum Fixture {
    static func main() throws {
        let examples = [
            "重庆银行":"isqkybhh", "音乐":"ybyt", "调试":"tnui", "女儿":"nver",
            "长安":"ihan", "软件":"rrjm", "方案":"fhan"
        ]
        for (word, expected) in examples {
            let actual = Flypy.code(for: word)
            precondition(actual == expected, "\(word) = \(actual ?? "?"), expected \(expected)")
        }
        let labels = ["重庆银行", "ScreenCaptureKit", "sample-creator-toolkit", "Shell Click", "Web search"]
        let image = NSImage(size: NSSize(width: 650, height: labels.count * 52))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black
        ]
        for (index, label) in labels.enumerated() {
            (label as NSString).draw(at: NSPoint(x: 24, y: 8 + index * 52), withAttributes: attributes)
        }
        image.unlockFocus()
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError() }
        let lines = try Recognition.lines(using: VNImageRequestHandler(cgImage: cg))
        let index = WordIndex()
        let entries = index.entries(lines: lines + ["查找 Data 页统计接口", "也统计接口", "重　庆  银行", "Local\u{00A0} Tools"])
        let samples = index.entries(lines: ["Local_API.Client–Kit", "Foo, Bar", "Alpha", "Beta", "Build - Tools"])
        precondition(samples.contains(Entry(code: "localapiclientkit", word: "Local_API.Client–Kit")))
        precondition(samples.contains(Entry(code: "buildtools", word: "Build - Tools")))
        precondition(!samples.contains { ["foobar", "alphabeta"].contains($0.code) })
        for entry in [Entry(code: "isqkybhh", word: "重庆银行"), Entry(code: "screencapturekit", word: "ScreenCaptureKit")] {
            precondition(entries.contains(entry), "OCR fixture \(lines) missing \(entry)")
        }
        precondition(entries.contains(Entry(code: "datayetsjijpkz", word: "Data 页统计接口")))
        let separated = index.entries(lines: ["Data", "页统计接口", "Data。页统计接口", "软 - 件"])
        precondition(!separated.contains { $0.code == "datayetsjijpkz" })
        precondition(!separated.contains { $0.word == "软 - 件" })
        let cache = try Snapshot(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let now = Date()
        let never = Entry(code: "rankexpired", word: "Rank Expired")
        let old = Entry(code: "rankold", word: "Rank Old")
        let recent = Entry(code: "rankrecent", word: "Rank Recent")
        let current = Entry(code: "rankvisible", word: "Rank Visible")
        try cache.replace([never, old, recent], now: now.addingTimeInterval(-900))
        // Static content stays visible for ten minutes. Retention starts on departure.
        try cache.heartbeat(now: now.addingTimeInterval(-301))
        try cache.replace([old, recent], now: now.addingTimeInterval(-300))
        cache.suspend(now: now.addingTimeInterval(-240))
        precondition(!FileManager.default.fileExists(atPath: cache.url.path))
        try cache.replace([recent], now: now.addingTimeInterval(-240))
        try cache.replace([], now: now.addingTimeInterval(-60))
        try cache.replace(entries + [current], now: now)
        let contents = try String(contentsOf: cache.url, encoding: .utf8)
        precondition(!contents.contains("Rank Expired") && contents.contains("Rank Old"))
        precondition(contents.contains("Rank Recent") && contents.contains("rankvisible\tRank Visible\t0"))
        print("Vision fixture, word extraction, polyphonic readings and snapshot OK")
    }
}
