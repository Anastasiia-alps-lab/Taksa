/* Taksa — the macOS build.
 *
 * SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The numbers and the placement maths, kept in one file so the two builds can
 * be compared side by side: everything here mirrors the core of the GNOME
 * extension, and a change on one side belongs on the other.
 */

import CoreGraphics
import Foundation

enum Burrow {
    /* On-screen size of the dog: a fraction of the screen width, clamped to a
     * sane range. The height follows from the artwork's aspect ratio.
     *
     * Unlike the GNOME build these are not multiplied by a scale factor: AppKit
     * measures in points, so a Retina display already reports half the pixels
     * and the same numbers give the same physical size. */
    static let widthFraction: CGFloat = 0.2
    static let widthRange: ClosedRange<CGFloat> = 200...900

    static let bottomMargin: CGFloat = 6 // gap under the lower dog
    static let menuBarGap: CGFloat = 8   // gap between the menu bar and the upper dog

    static let moveDuration: CFTimeInterval = 2.5 // the dog crawls, it never teleports
    static let debounce: TimeInterval = 0.4       // one save fires a burst of file events
    static let pollInterval: TimeInterval = 300   // safety net in case the watcher misses one
    static let staleAfter: TimeInterval = 2 * 60 * 60

    static let maxStateBytes = 64 * 1024 // anything larger is not our state file

    /// Aspect ratio used when there is no artwork to measure. It only decides
    /// the shape of a figure that has nothing to draw, so it never shows.
    static let placeholderAspect: CGFloat = 160.0 / 60.0
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Where the two halves of the dog sit, and how far the figure inside each of
/// them is shifted for a given percentage.
struct BurrowGeometry {
    let figureSize: CGSize
    let bottomFrame: CGRect
    let topFrame: CGRect

    /// `area` is the screen's visible frame — the full screen minus the menu bar
    /// and the Dock. Using it instead of the raw frame is what keeps the Dock
    /// from swallowing the lower dog; both frames still sit flush against their
    /// corner of that area, which is what makes the two halves add up to one
    /// whole dog.
    ///
    /// AppKit's origin is the bottom-left corner and y grows upwards, so the
    /// lower dog is the one with the smaller y.
    init(area: CGRect, aspect: CGFloat) {
        let width = (area.width * Burrow.widthFraction).clamped(to: Burrow.widthRange).rounded()
        let height = (width / aspect).rounded()

        figureSize = CGSize(width: width, height: height)
        bottomFrame = CGRect(x: area.minX, y: area.minY + Burrow.bottomMargin,
                             width: width, height: height)
        topFrame = CGRect(x: area.maxX - width, y: area.maxY - height - Burrow.menuBarGap,
                          width: width, height: height)
    }

    /// The dog's own length is the scale: the share of its body sticking out of
    /// the top-right corner is the share of the limit that is gone, and exactly
    /// the missing part is left at the bottom left.
    ///
    /// A single number defines the cut: `gone`, the length already underground.
    /// It is rounded once for both halves, otherwise a pixel wanders at the seam.
    func offsets(percent: Double) -> (bottom: CGFloat, top: CGFloat) {
        let gone = (figureSize.width * CGFloat(percent.clamped(to: 0...100)) / 100).rounded()
        // 0%: flush with the left edge, 100%: entirely past it.
        // 0%: entirely past the right edge, 100%: fully out.
        return (-gone, figureSize.width - gone)
    }
}
