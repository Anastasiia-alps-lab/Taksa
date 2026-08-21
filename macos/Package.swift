// swift-tools-version:5.9
//
// SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

// The package builds a bare executable; build-app.sh wraps it into Taksa.app
// together with Info.plist and the artwork. Nothing here depends on anything
// outside the standard macOS frameworks.
let package = Package(
    name: "Taksa",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Taksa", path: "Sources/Taksa"),
    ]
)
