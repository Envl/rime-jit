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
final class ScreenReader: NSObject, SCStreamOutput, SCStreamDelegate {
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

    @MainActor func start(displayID: CGDirectDisplayID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "RimeScreenWords", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到所选显示器"])
        }
        let excluded = Set(["im.rime.inputmethod.Squirrel", Bundle.main.bundleIdentifier ?? ""])
        let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter {
            excluded.contains($0.bundleIdentifier)
        }, exceptingWindows: [])
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
