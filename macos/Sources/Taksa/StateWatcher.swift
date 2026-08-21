/* Taksa — the macOS build.
 *
 * SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import CoreServices
import Foundation

/// Watches the state directory and reports changes on the main queue, debounced.
///
/// FSEvents is the macOS counterpart of Gio.FileMonitor. The file-level flag
/// makes it report writes *inside* the directory and not only entries appearing
/// and disappearing, so a writer that rewrites its file in place is caught too.
/// A single save still fires a burst of events, hence the same 400 ms debounce
/// the GNOME build uses.
final class StateWatcher {
    private let directory: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "alps.taksa.fsevents")

    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }

        /* The callback is a C function pointer and cannot capture anything, so
         * the watcher travels through the stream's context as a raw pointer.
         * It is passed unretained: start() and stop() are called by the owner,
         * which outlives the stream. */
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<StateWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
            },
            &context,
            [directory.path] as CFArray,
            // An unsigned -1: start from whatever happens from now on.
            FSEventStreamEventId(truncatingIfNeeded: kFSEventStreamEventIdSinceNow),
            0.1, // FSEvents' own coalescing window; the debounce below does the rest
            FSEventStreamCreateFlags(flags))
        else {
            NSLog("Taksa: cannot watch %@", directory.path)
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            NSLog("Taksa: cannot start watching %@", directory.path)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }

        self.stream = stream
    }

    /// Undoes start() completely: no callback can fire afterwards.
    func stop() {
        pending?.cancel()
        pending = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func schedule() {
        DispatchQueue.main.async { [self] in
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pending = nil
                self?.onChange()
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Burrow.debounce, execute: work)
        }
    }
}
