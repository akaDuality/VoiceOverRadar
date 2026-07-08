import ProjectDescription

let project = Project(
    name: "VoiceOverSatelite",
    // Consume the AXCore accessibility logic as a local Swift Package module.
    packages: [
        .package(path: "Packages/AXCore"),
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
    ]),
    targets: [
        .target(
            name: "VoiceOverSatelite",
            destinations: .macOS,
            product: .app,
            bundleId: "com.devicehub.voiceoversatelite",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .extendingDefault(with: [
                // Dev-friendly: show a Dock icon + window. Set LSUIElement to
                // true to ship as a pure menu-bar agent (no Dock icon/window).
                "CFBundleDisplayName": "VoiceOver Satelite",
                // Allow plain-HTTP requests to the local exporter endpoint.
                "NSAppTransportSecurity": [
                    "NSAllowsLocalNetworking": true,
                ],
            ]),
            sources: ["App/Sources/**"],
            entitlements: .file(path: "App/VoiceOverSatelite.entitlements"),
            dependencies: [
                .package(product: "AXCore"),
            ],
            // A real (non-adhoc) signature keeps the Accessibility grant stable
            // across rebuilds. Change DEVELOPMENT_TEAM to your own team id.
            settings: .settings(base: [
                // Manual signing against the keychain's Apple Development cert.
                // macOS allows dev-signing with no provisioning profile, and a
                // real team-based signature keeps the Accessibility grant stable
                // across rebuilds (ad-hoc "-" would reset it every build).
                "CODE_SIGN_STYLE": "Manual",
                // Exact keychain identity by SHA-1 (Apple Development: Mikhail
                // Rubanov / FSA7H6VL3A) — bypasses account/profile resolution.
                "CODE_SIGN_IDENTITY": "37F0A1942289D89E7F0E07298265E2156D2125A1",
                "DEVELOPMENT_TEAM": "FSA7H6VL3A",
                "PROVISIONING_PROFILE_SPECIFIER": "",
            ])
        ),
    ]
)
