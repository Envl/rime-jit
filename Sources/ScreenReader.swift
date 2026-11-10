import AppKit
import ScreenCaptureKit
import Vision

enum Recognition {
    static func lines(using handler: VNImageRequestHandler) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.automaticallyDetectsLanguage = true
        try handler.perform([request])
        return (request.results ?? []).compactMap { result in
            guard let match = result.topCandidates(1).first, match.confidence >= 0.45 else { return nil }
            return match.string
        }
    }
}

// Each capture session owns its queue and tokenizer. Drop results from stopped sessions in the UI.
private final class DisplayReader: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "RimeScreenWords.recognition", qos: .utility)
    private let index = WordIndex()
    private var lastLines: [String]?
    private var stream: SCStream?
    let update: ([Entry]) -> Void
    let failure: (Error) -> Void

    init(update: @escaping ([Entry]) -> Void, failure: @escaping (Error) -> Void) {
        self.update = update
        self.failure = failure
    }

    @MainActor func start(filter: SCContentFilter) async throws {
        let config = SCStreamConfiguration()
        let scale = min(CGFloat(filter.pointPixelScale), 3072 / max(1, filter.contentRect.width))
        config.width = max(1, Int(filter.contentRect.width * scale))
        config.height = max(1, Int(filter.contentRect.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        let capture = SCStream(filter: filter, configuration: config, delegate: self)
        try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        stream = capture
        try await capture.startCapture()
    }

    @MainActor func stop() async {
        let capture = stream
        stream = nil
        try? await capture?.stopCapture()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.failure(error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let data = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = data.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw)
        else { return }
        if status == .idle || status == .started { return }
        do {
            let lines: [String]
            if status == .complete, let buffer = sample.imageBuffer {
                lines = try Recognition.lines(using: VNImageRequestHandler(cvPixelBuffer: buffer))
            } else {
                lines = []
            }
            guard lines != lastLines else { return }
            lastLines = lines
            let entries = index.entries(lines: lines)
            DispatchQueue.main.async { self.update(entries) }
        } catch {
            DispatchQueue.main.async { self.failure(error) }
        }
    }
}

// Keep each display's most recent result until that display changes or leaves.
@MainActor
final class ScreenReader {
    private struct Capture {
        let id: UUID
        let reader: DisplayReader
        let size: CGSize
        let scale: Float
    }

    private let update: ([Entry]) -> Void
    private let status: (Int, Error?) -> Void
    private var captures: [CGDirectDisplayID: Capture] = [:]
    private var words: [CGDirectDisplayID: [Entry]] = [:]
    private var errors: [CGDirectDisplayID: Error] = [:]
    private var refreshing = false
    private var needsRefresh = false
    private var stopped = false

    init(update: @escaping ([Entry]) -> Void, status: @escaping (Int, Error?) -> Void) {
        self.update = update
        self.status = status
    }

    // Coalesce notifications received while ScreenCaptureKit is enumerating or starting.
    func refresh(retryFailed: Bool = true) {
        guard !stopped else { return }
        if retryFailed { errors.removeAll() }
        needsRefresh = true
        guard !refreshing else { return }
        refreshing = true
        Task {
            while needsRefresh && !stopped {
                needsRefresh = false
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    if stopped || needsRefresh { continue }
                    await reconcile(content)
                    if !stopped && !needsRefresh { status(captures.count, errors.values.first) }
                } catch {
                    if !stopped && !needsRefresh { status(captures.count, error) }
                }
            }
            refreshing = false
        }
    }

    private func reconcile(_ content: SCShareableContent) async {
        let displays = content.displays.filter { CGDisplayMirrorsDisplay($0.displayID) == kCGNullDirectDisplay }
        let connected = Set(displays.map(\.displayID))
        errors = errors.filter { connected.contains($0.key) }
        for id in Set(captures.keys).subtracting(connected) { remove(id) }
        let excluded = content.applications.filter {
            $0.bundleIdentifier == "im.rime.inputmethod.Squirrel" || $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        for display in displays {
            guard !stopped && !needsRefresh else { return }
            let id = display.displayID
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            if let existing = captures[id] {
                if existing.size == filter.contentRect.size && existing.scale == filter.pointPixelScale { continue }
                remove(id)
            }
            guard errors[id] == nil else { continue }
            let token = UUID()
            let reader = DisplayReader(update: { [weak self] entries in
                guard let self, self.captures[id]?.id == token else { return }
                self.words[id] = entries
                self.publish()
            }, failure: { [weak self] error in
                guard let self, self.captures[id]?.id == token else { return }
                self.errors[id] = error
                self.remove(id)
                self.refresh(retryFailed: false)
            })
            captures[id] = Capture(id: token, reader: reader, size: filter.contentRect.size, scale: filter.pointPixelScale)
            do { try await reader.start(filter: filter) }
            catch {
                if captures[id]?.id == token {
                    errors[id] = error
                    remove(id)
                }
            }
        }
    }

    private func publish() { update(words.values.flatMap { $0 }) }

    private func remove(_ id: CGDirectDisplayID) {
        guard let capture = captures.removeValue(forKey: id) else { return }
        if words.removeValue(forKey: id) != nil && !stopped { publish() }
        Task { await capture.reader.stop() }
    }

    func stop() {
        stopped = true
        for id in Array(captures.keys) { remove(id) }
    }
}
