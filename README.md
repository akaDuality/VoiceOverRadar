# VoiceOver Radar

A macOS companion app that reads a **live iOS accessibility tree** from a running
app and lets you inspect and drive it from your Mac — like a VoiceOver console
sitting next to the Simulator.

It pairs with [**VoiceOverRadarKit**](https://github.com/akaDuality/VoiceOverRadarKit),
a tiny Swift package you embed in the iOS app that streams its `UIAccessibility`
tree over `http://localhost:8765/`. VoiceOver Radar is the companion that reads
and drives it.

> The host AX API can't see inside the iOS Simulator, so the tree is sourced from
> inside the app (via VoiceOverRadarKit). VoiceOver Radar only uses the
> macOS Accessibility API to locate the Simulator's device rect on screen, for
> outlines and taps.

## What it does

- **Element list** in VoiceOver reading order (top-to-bottom, left-to-right),
  each row showing the label/value and traits.
- **Hover to locate** — hovering a row paints every element on the Simulator with
  a translucent colour and outlines the hovered one.
- **Tap to drive** — clicking a row taps the matching control in the Simulator.
- **Adjustable controls** — `− / +` buttons for `.adjustable` elements (sliders,
  steppers), performed as real UIKit increments in the app.
- **Custom actions** — a button per `accessibilityCustomAction`.
- **Custom content** — extra `accessibilityCustomContent` shown under the label.
- **Popover/sheet detection** — a banner appears and the list scopes to the modal
  (via the content-bearing `accessibilityViewIsModal` branch), like VoiceOver.
- **Gestures** — Magic Tap and Scrub (escape / dismiss) buttons.
- **Companion window** — chromeless, blurred, docks beside the Simulator, matches
  its height, and follows it when moved.

## How it works

1. Polls `http://localhost:8765/` for the JSON accessibility snapshot.
2. Reads the Simulator's on-screen device rect via the macOS AX API
   (the `iOSContentGroup` element) to map iOS points → Mac-screen points.
3. Outlines use a floating overlay window; taps post a click at the mapped point;
   adjust/action/gesture commands go back to the app through the stream's
   `/action` endpoint (real UIKit calls, no synthetic input).

## Requirements

- macOS 13+, Xcode 26+, [Tuist](https://tuist.dev).
- **Accessibility permission** (for Simulator outlines/taps) — grant on first run.
- The target iOS app must embed **VoiceOverRadarKit** and call
  `VoiceOverRadarKit.shared.start()` (DEBUG).

## Build & run

```bash
cd VoiceOverRadar
tuist generate
open VoiceOverRadar.xcworkspace
```

Set your Team in Signing, Run, and grant Accessibility access when prompted.
Then run the iOS app in the Simulator — the element list fills in automatically.

> Signing note: the project uses manual signing against a specific Apple
> Development identity so the Accessibility grant survives rebuilds (ad-hoc
> signatures reset it). Change `DEVELOPMENT_TEAM` / `CODE_SIGN_IDENTITY` in
> `VoiceOverRadar/Project.swift` to your own.

## Layout

```
VoiceOverRadar/
├── Project.swift · Tuist.swift        # Tuist project (generates the workspace)
├── App/Sources/                       # SwiftUI app: list, overlay, tap/gesture input
└── Packages/AXCore/                   # Swift package: exporter client, screen geometry,
                                       #   VoiceOver-style descriptions, AX helpers
```

## See also

- [VoiceOverRadarKit](https://github.com/akaDuality/VoiceOverRadarKit)
  — the iOS package that streams the tree this app reads.
