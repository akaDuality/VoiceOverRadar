# VoiceOverDeviceHub

A macOS tool (for DeviceHub) that shows a live, VoiceOver-style description of
the currently focused element on screen, by reading the same Accessibility (AX)
tree VoiceOver reads.

The Xcode project lives in [`VoiceOverInspector/`](VoiceOverInspector/) — see its
README for build/run and architecture. Core AX logic is the `AXCore` Swift
package; the app is a thin SwiftUI shell.

## Working rules

- **Commit after every completed change.** Once a change is finished and builds,
  make a focused git commit for it before moving on. Keep commits small and
  scoped to one change.
