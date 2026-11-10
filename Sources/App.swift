import AppKit
import Carbon

@main
@MainActor
final class App: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let toggle = NSMenuItem()
    private var cache: Snapshot?
    private var reader: ScreenReader?
    private var session = UUID()
    private var timer: Timer?
    private var pending = false

    static func main() {
        let app = NSApplication.shared
        let delegate = App()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "屏幕候选词")
        let menu = NSMenu()
        toggle.target = self
        toggle.action = #selector(toggleCapture)
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出屏幕候选词", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        status.menu = menu
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/RimeScreenWords")
        do { cache = try Snapshot(directory: directory) }
        catch { show(error) }
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(self, selector: #selector(stop), name: event, object: nil)
        }
        render()
    }

    private func render() {
        let active = reader != nil
        toggle.title = active ? "暂停屏幕取词" : "开始屏幕取词"
        toggle.isEnabled = cache != nil
        status.button?.contentTintColor = active ? .systemGreen : nil
        status.button?.toolTip = pending ? "正在启动屏幕取词" : (active ? "屏幕取词中" : "屏幕取词已暂停")
    }

    @objc private func toggleCapture() {
        if reader != nil { stop(); return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            let alert = NSAlert()
            alert.messageText = "需要屏幕录制权限"
            alert.informativeText = "在系统设置中允许 RimeScreenWords 录制屏幕，然后重新打开应用并开始取词。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let id = UUID()
        session = id
        let capture = ScreenReader(update: { [weak self] entries in
            guard let self, self.session == id else { return }
            if IsSecureEventInputEnabled() { self.stop(); return }
            do { try self.cache?.replace(entries) }
            catch { self.fail(error) }
        }, failure: { [weak self] error in
            guard let self, self.session == id else { return }
            self.fail(error)
        })
        reader = capture
        pending = true
        render()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
        Task {
            do {
                try await capture.start(displayID: displayID)
                guard session == id else { await capture.stop(); return }
                pending = false
                render()
                // Common modes keep lease expiry independent of an open menu.
                let clock = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
                RunLoop.main.add(clock, forMode: .common)
                timer = clock
            } catch { if session == id { fail(error) } }
        }
    }

    @objc private func tick() {
        if IsSecureEventInputEnabled() { stop(); return }
        do { try cache?.heartbeat() }
        catch { fail(error) }
    }

    @objc private func stop() {
        session = UUID()
        let previous = reader
        reader = nil
        pending = false
        timer?.invalidate()
        timer = nil
        cache?.clear()
        Task { await previous?.stop() }
        render()
    }

    private func fail(_ error: Error) {
        stop()
        show(error)
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) { cache?.clear() }
}
