/* Taksa — the macOS build.
 *
 * SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate

/* A menu bar agent: no Dock icon, no entry in the app switcher, never the
 * active application. Info.plist says the same with LSUIElement, but that file
 * only exists inside the bundle — this line keeps `swift run` behaving the same
 * way while working on the app. */
application.setActivationPolicy(.accessory)
application.run()
