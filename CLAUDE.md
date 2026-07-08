# VoiceOver Satelite

A macOS companion app that reads an iOS app's live accessibility tree (served by
[AccessibilityTreeStream](https://github.com/akaDuality/AccessibilityTreeStream))
and lets you inspect and drive it — element list, Simulator outlines, taps,
adjustable/custom actions, and VoiceOver gestures.

The Xcode project lives in [`VoiceOverSatelite/`](VoiceOverSatelite/). Core logic
is the `AXCore` Swift package; the app is a thin SwiftUI shell.

## Working rules

- **Commit after every completed change.** Once a change is finished and builds,
  make a focused git commit for it before moving on. Keep commits small and
  scoped to one change.
