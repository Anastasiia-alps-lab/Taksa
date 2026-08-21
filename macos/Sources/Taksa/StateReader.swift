/* Taksa — the macOS build.
 *
 * SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import Foundation

/// One state file, reduced to the fields the dog needs. A file that is missing,
/// half-written or shaped differently simply fails to decode and is skipped.
private struct StateFile: Decodable {
    let fiveHour: Double?
    let sevenDay: Double?
    let updatedAt: Double?
    let isOverride: Bool?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case updatedAt = "updated_at"
        case isOverride = "override"
    }
}

enum StateReader {
    /// The same directory the GNOME build reads, so a single writer feeds both.
    ///
    /// An app launched from Finder inherits no shell environment, so
    /// XDG_STATE_HOME is normally unset here and the default path wins — which
    /// is exactly what the scripts write to.
    static var directory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let base = environment["XDG_STATE_HOME"], !base.isEmpty {
            return URL(fileURLWithPath: base, isDirectory: true)
                .appendingPathComponent("taksa", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/taksa", isDirectory: true)
    }

    /// Every *.json file in the state directory is an independent source. Stale
    /// ones are dropped, and of the rest the largest of five_hour / seven_day
    /// wins — the scary number is the limit that runs out first.
    ///
    /// A file with "override": true beats the others, which is how taksa-test.sh
    /// can show 0% while a fresh claude-code.json sits next to it.
    ///
    /// Called on a background queue: blocking on a slow disk here costs a late
    /// refresh and nothing else, the interface never waits for it.
    static func currentPercent() -> Double? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles])) ?? [] // no state directory yet — nothing to show

        let now = Date().timeIntervalSince1970
        var best: Double?
        var override: Double?

        for file in files where file.pathExtension == "json" {
            guard let sample = read(file, now: now) else { continue }
            if sample.isOverride {
                override = max(override ?? sample.percent, sample.percent)
            } else {
                best = max(best ?? sample.percent, sample.percent)
            }
        }

        return override ?? best
    }

    /// One state file: its percentage, or nil if it is unusable or stale.
    private static func read(_ file: URL, now: TimeInterval) -> (percent: Double, isOverride: Bool)? {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Burrow.maxStateBytes else { return nil }

        guard let data = try? Data(contentsOf: file),
              let state = try? JSONDecoder().decode(StateFile.self, from: data)
        else { return nil }

        guard let updatedAt = state.updatedAt, now - updatedAt <= Burrow.staleAfter else { return nil }

        let values = [state.fiveHour, state.sevenDay].compactMap { $0 }.filter { $0.isFinite }
        guard let percent = values.max() else { return nil }

        return (percent, state.isOverride == true)
    }
}
