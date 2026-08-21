/* Taksa — the macOS build.
 *
 * SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import AppKit

/// One half of the dog: a borderless, click-through window parked against a
/// screen corner with the artwork sliding sideways inside it. Whatever leaves
/// the window is clipped away, which is what turns the dog's own length into
/// the scale.
///
/// The window is composed rather than subclassed — nothing here needs a custom
/// NSWindow, and a plain object keeps the initialiser free of NSCoding.
final class FigureWindow {
    private static let crawlKey = "taksa.crawl"

    private let window: NSWindow
    private let figure = CALayer()

    init(image: CGImage?) {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                          styleMask: .borderless, backing: .buffered, defer: false)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true // the dog never takes a click
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none // no fade when it is ordered in
        window.level = .floating         // above ordinary windows, below the menu bar

        /* canJoinAllSpaces keeps the dog on every desktop, and leaving out
         * fullScreenAuxiliary keeps it off the space a full-screen app owns —
         * together they are the AppKit spelling of the GNOME build's
         * trackFullscreen. fullScreenNone says the same thing outright. */
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]

        let host = NSView(frame: .zero)
        host.wantsLayer = true
        host.layer?.masksToBounds = true // the clip that cuts the dog in half
        window.contentView = host

        /* Anchored at its own bottom-left corner, so `position.x` is simply how
         * far the figure is shifted inside the window. */
        figure.anchorPoint = CGPoint(x: 0, y: 0)
        figure.position = .zero
        figure.contentsGravity = .resize
        if let image {
            figure.contents = image
        }
        /* Nothing is drawn until a usage percentage is actually known. The
         * window itself stays ordered in: it is fully transparent and takes no
         * input, so an empty one costs nothing. */
        figure.isHidden = true
        // Implicit animations would fight the explicit crawl in move(to:).
        figure.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "contents": NSNull(),
            "hidden": NSNull(),
        ]
        host.layer?.addSublayer(figure)
    }

    /// Parks the window in its corner and resizes the figure to match.
    func setGeometry(frame: CGRect, figureSize: CGSize) {
        window.setFrame(frame, display: true)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        figure.bounds = CGRect(origin: .zero, size: figureSize)
        /* Points, not pixels: the layer needs the backing scale to draw the
         * artwork at full resolution on a Retina display. The primary screen's
         * scale cannot change without a screen-parameters notification, and
         * that is what brought us here. */
        figure.contentsScale = window.backingScaleFactor
        CATransaction.commit()

        window.orderFrontRegardless()
    }

    func setFigureVisible(_ visible: Bool) {
        figure.isHidden = !visible
    }

    /// Moves the figure to `x` inside the window, crawling there when asked.
    func move(to x: CGFloat, animated: Bool) {
        let target = CGPoint(x: x, y: 0)
        // Read the presentation layer first: after removeAnimation it snaps
        // back to the model value and a re-targeted crawl would jump.
        let current = figure.presentation()?.position ?? figure.position

        figure.removeAnimation(forKey: Self.crawlKey)
        figure.position = target
        guard animated else { return }

        let crawl = CABasicAnimation(keyPath: "position")
        crawl.fromValue = NSValue(point: current)
        crawl.toValue = NSValue(point: target)
        crawl.duration = Burrow.moveDuration
        // ease-out-cubic, the curve the GNOME build eases with
        crawl.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        figure.add(crawl, forKey: Self.crawlKey)
    }

    func close() {
        figure.removeAllAnimations()
        window.orderOut(nil)
        window.close()
    }
}
