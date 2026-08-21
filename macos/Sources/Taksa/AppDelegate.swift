/* Taksa — the macOS build.
 *
 * SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A dachshund digs into a burrow: the more of the Claude Code usage limit is
 * spent, the further it disappears past the bottom-left corner of the screen —
 * and the further it emerges from the top-right one. The menu bar carries the
 * same number in percent.
 */

import AppKit
import ImageIO
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var launchItem: NSMenuItem?

    private var bottomWindow: FigureWindow?
    private var topWindow: FigureWindow?

    private var watcher: StateWatcher?
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    private let readQueue = DispatchQueue(label: "alps.taksa.state", qos: .utility)

    private var aspect = Burrow.placeholderAspect
    private var geometry: BurrowGeometry?
    private var percent: Double?
    private var generation = 0

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let figure = Self.loadFigure()
        if let figure {
            aspect = CGFloat(figure.width) / CGFloat(figure.height)
        } else {
            NSLog("Taksa: no taksa.png to draw, only the menu bar item will work")
        }

        bottomWindow = FigureWindow(image: figure)
        topWindow = FigureWindow(image: figure)

        buildStatusItem()

        let directory = StateReader.directory
        // Created up front so the watcher below has something to watch; the
        // writers (statusline-taksa.sh and friends) own the contents.
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        watcher = StateWatcher(directory: directory) { [weak self] in
            self?.refresh(animated: true)
        }
        watcher?.start()

        pollTimer = Timer.scheduledTimer(withTimeInterval: Burrow.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh(animated: true)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.relayout()
        }

        relayout()
        refresh(animated: false)
    }

    /// Undoes everything applicationDidFinishLaunching() set up. Quitting would
    /// free it all anyway; doing it by hand keeps the teardown honest and
    /// mirrors the GNOME build, where a leak is grounds for rejection.
    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        watcher = nil

        pollTimer?.invalidate()
        pollTimer = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil

        bottomWindow?.close()
        topWindow?.close()
        bottomWindow = nil
        topWindow = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        launchItem = nil

        percent = nil
    }

    /// The one place where the artwork is loaded. taksa.png ships inside the
    /// bundle; TAKSA_FIGURE points somewhere else, which is what makes a plain
    /// `swift run` usable while working on the app.
    private static func loadFigure() -> CGImage? {
        var url = Bundle.main.url(forResource: "taksa", withExtension: "png")
        if let path = ProcessInfo.processInfo.environment["TAKSA_FIGURE"], !path.isEmpty {
            url = URL(fileURLWithPath: path)
        }

        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        return image
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self

        let launch = NSMenuItem(title: "Open at Login",
                                action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launch.target = self
        menu.addItem(launch)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Taksa",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        launchItem = launch

        setStatusTitle(for: nil)
    }

    /// The checkmark is read back from the system every time the menu opens, so
    /// a registration that silently failed cannot leave a lying tick behind.
    func menuWillOpen(_ menu: NSMenu) {
        launchItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Fails when the app runs outside a bundle, which is the normal
            // state of affairs under `swift run`.
            NSLog("Taksa: cannot change the login item: %@", error.localizedDescription)
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func setStatusTitle(for value: Double?) {
        let text = value.map { "🐕 \(Int($0.clamped(to: 0...100).rounded()))%" } ?? "🐕 —"
        // Monospaced digits so the item does not twitch as the number changes.
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .semibold)
        statusItem?.button?.attributedTitle = NSAttributedString(
            string: text, attributes: [.font: font])
    }

    // MARK: - Reading

    /// Reads the state directory off the main queue and applies the result. A
    /// newer refresh started while one is in flight wins, whatever the
    /// completion order.
    private func refresh(animated: Bool) {
        generation += 1
        let token = generation

        readQueue.async { [weak self] in
            let value = StateReader.currentPercent()
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.apply(value, animated: animated)
            }
        }
    }

    private func apply(_ value: Double?, animated: Bool) {
        setStatusTitle(for: value)

        /* No data means "unknown", not "0% spent": a new session has not made a
         * request yet, the file went stale, the source disappeared. The dog
         * stays where it was and the menu bar honestly shows a dash. Crawling
         * back to the start would look like a limit reset that never happened. */
        guard let value else { return }

        // The very first reading is placed without animation: there is no
        // previous position to crawl away from.
        let known = percent != nil
        let changed = value != percent
        percent = value

        /* A writer re-stamps its state file on every status line, so most
         * refreshes carry the same number as the one before. Re-placing on those
         * would kill the running transition and snap the dog to its target: a
         * crawl started two seconds ago would end in a jump. */
        if known && !changed { return }

        place(animated: animated && changed && known)
    }

    // MARK: - Placement

    /// Geometry for the current screen: where the windows sit and how big the
    /// dog is. The primary screen is always the first one — the display the
    /// menu bar lives on.
    private func relayout() {
        guard let screen = NSScreen.screens.first,
              let bottomWindow, let topWindow
        else { return }

        let geometry = BurrowGeometry(area: screen.visibleFrame, aspect: aspect)
        self.geometry = geometry

        bottomWindow.setGeometry(frame: geometry.bottomFrame, figureSize: geometry.figureSize)
        topWindow.setGeometry(frame: geometry.topFrame, figureSize: geometry.figureSize)

        place(animated: false)
    }

    private func place(animated: Bool) {
        guard let geometry, let bottomWindow, let topWindow else { return }

        guard let percent else {
            // Before the first ever reading nothing is drawn at all.
            bottomWindow.setFigureVisible(false)
            topWindow.setFigureVisible(false)
            return
        }

        let offsets = geometry.offsets(percent: percent)
        bottomWindow.setFigureVisible(true)
        topWindow.setFigureVisible(true)
        bottomWindow.move(to: offsets.bottom, animated: animated)
        topWindow.move(to: offsets.top, animated: animated)
    }
}
