# VoiceOver Inspector

A macOS menu-bar tool for **DeviceHub** that shows a live, VoiceOver-style
description of whatever is focused on the current screen. It reads the same
Accessibility (AX) tree VoiceOver reads, and reconstructs the phrase VoiceOver
would announce.

> **Note:** macOS exposes no public API for VoiceOver's *actual* spoken string.
> This tool composes a VoiceOver-*equivalent* description from the underlying
> attributes (label → value → role → hint). It matches what you hear in the vast
> majority of cases.

## Layout

```
VoiceOverInspector/
├── Tuist.swift                 # Tuist config (local, no account needed)
├── Project.swift               # App project — consumes AXCore as a package
├── App/
│   ├── Sources/                # SwiftUI menu-bar app
│   └── VoiceOverInspector.entitlements
└── Packages/
    └── AXCore/                 # Swift Package module: all the AX logic
        ├── Sources/AXCore/
        └── Tests/AXCoreTests/
```

- **`AXCore`** (Swift Package) — permission handling, attribute reading,
  VoiceOver-style description composition, and a live `AXObserver`-based
  `ScreenAccessibilityMonitor`. Framework-agnostic and unit-tested.
- **App** — a thin SwiftUI `MenuBarExtra` that binds to the monitor.

## Build & run

Requires Xcode 26+ and [Tuist](https://tuist.dev) (already available here).

```bash
cd VoiceOverInspector
tuist generate          # emits VoiceOverInspector.xcworkspace
open VoiceOverInspector.xcworkspace
```

Select the **VoiceOverInspector** scheme and run. Or work on the core alone:

```bash
cd Packages/AXCore && swift test
```

## Permissions & signing (important)

1. **Accessibility access** — on first run, click *Grant Access…* in the popover.
   The app appears under **System Settings → Privacy & Security → Accessibility**.
2. **Non-sandboxed** — reading *other* apps' AX trees is forbidden by the App
   Sandbox, so this ships as a Developer ID app outside the Mac App Store. The
   entitlements file disables the sandbox.
3. **Signing** — set your Team in the target's Signing settings before running
   from Xcode. Note: ad-hoc / "Sign to Run Locally" builds get a fresh identity
   on some rebuilds, which can reset the Accessibility grant — re-grant if so.

## How it works

| Piece | AX mechanism |
|-------|--------------|
| Is the current app readable? | `AXIsProcessTrusted()` |
| Which app is on screen? | `NSWorkspace.frontmostApplication` + activation notifications |
| What is focused? | `kAXFocusedUIElementAttribute` on the app element |
| The whole screen | `kAXFocusedWindowAttribute` → recurse `kAXChildrenAttribute` |
| Live updates | `AXObserver` on focus/value/selection/window changes |
| The spoken phrase | `kAXTitle` / `kAXDescription` + `kAXValue` + `kAXRoleDescription` + `kAXHelp` |
