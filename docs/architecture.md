# Architecture

This document describes the app structure and data flow of `turtlemeck` for contributors working with the codebase.
For user-facing behavior, start with the [`turtlemeck` documentation](README.md).

## App shape

`turtlemeck` is a native macOS app with no server or web interface.
In normal mode, it runs as an `LSUIElement` menu bar app without a Dock icon or main window.
With `--debug`, it shows the same SwiftUI interface and additional debugging information in a resizable standard window instead of the menu bar.

The Swift package has no external package dependencies and defines the following products and executable targets.

| Component | Role |
|---|---|
| `TurtleCore` | Library containing the app, camera, inference, evaluation, notification, and storage logic |
| `turtlemeck` | Entry point for the macOS app |
| `analyze-image` | Development tool for inspecting 2D posture and relative-depth features in saved images |
| `workflow-tests` | SwiftPM executable test runner |

## Composition root

`Sources/turtlemeck/main.swift` calls `runTurtleMeckApp()`.
That function, defined in `Sources/TurtleCore/App/Entry.swift`, creates, retains, and installs `AppDelegate`.
`AppDelegate` creates one `AppModel` and connects it to either `StatusItemController` or a debug `NSWindow`, depending on the launch mode.

`AppModel` owns the UI state and coordinates the lifecycles of the following components.

- `CameraManager` — reserves the camera, captures frames, and runs the inference and evaluation pipeline
- `SettingsStore`, `StatsStore` — store the baseline posture, settings, and daily statistics
- `PostureStateMachine` — applies persistence rules to posture evidence and produces `good`, `bad`, and `noEval` transitions and events; `AppModel` owns the remaining lifecycle states
- `NotificationPolicy`, `NotificationManager` — handle repeat limits, snoozing, and banner and sound delivery

Callbacks from the camera layer pass evaluation results, the next check time, camera blocking, diagnostics, and capture activity to `AppModel`.
The UI observes the published state of `AppModel`.

## Analysis pipeline

Each posture check follows this sequence.

1. `CameraManager` opens the built-in camera at 640×480 and selects up to 5 frames after a warm-up period.
2. `PoseDetector` prefers PoseNet and falls back to Apple Vision 2D when PoseNet does not provide a usable upper-body candidate.
3. `CoreMLRelativeDepthProvider` uses Depth Anything V2 Small to create a relative depth map.
4. `UpperBodySubjectSelector` selects one subject candidate, and `PostureFrameAnalyzer` derives features for comparison with the baseline from that subject's head, torso, and reference ROIs.
5. `BurstProcessor` aggregates frame medians and quality, then compares them with the stored baseline posture.
6. `PostureStateMachine` applies persistence to normal, degraded, and indeterminate evidence and produces `good`, `bad`, or `noEval` transitions and statistics events.
7. `AppModel` updates the UI and statistics, and sends only poor-state events permitted by `NotificationPolicy`.

Debug and local output is written on a separate output queue after the product state has been determined.
Output delays, failures, and local AI results never feed back into posture evaluation.
For the detailed evaluation contract, see the [posture analysis workflow (Korean only)](workflow.md).

## Source layout

| Directory | Responsibility |
|---|---|
| `Sources/TurtleCore/App/` | App lifecycle, launch modes, and UI state coordination |
| `Sources/TurtleCore/Camera/` | Permissions, capture session, burst scheduling, and frame-quality gates |
| `Sources/TurtleCore/Inference/` | PoseNet and Depth Anything V2 Core ML adapters, plus the Apple Vision 2D fallback |
| `Sources/TurtleCore/Detection/` | Subject selection, ROIs and features, calibration, burst evaluation, state transitions, and tuning values |
| `Sources/TurtleCore/MenuBar/` | `NSStatusItem`, `NSPopover`, and the shared SwiftUI `MenuView` |
| `Sources/TurtleCore/Notifications/` | Notification repetition policy and macOS banner and sound delivery |
| `Sources/TurtleCore/Storage/` | UserDefaults settings and baseline posture, plus JSON daily statistics |
| `Sources/TurtleCore/Output/` | Debug and local artifacts that do not affect evaluation |
| `Sources/TurtleCore/Launch/` | `SMAppService` login-item status lookup, registration, and removal |

## State and persistence

| State | Owner | Persistence |
|---|---|---|
| Current posture state, next check, and pause state | `AppModel` | Resets to the initial state when the app restarts. |
| Consecutive degraded, recovered, and indeterminate counts | `PostureStateMachine` | Memory only. |
| Notification minimum interval and snooze | `NotificationPolicy` | Memory only. |
| Check interval, notification settings, and baseline posture | `SettingsStore` | Stored in UserDefaults. The `--debug` launch state is not stored. |
| Daily good and poor posture time, plus event counts | `StatsStore` | Stored in `Application Support/turtlemeck/stats.json`. |

At launch, the app reads the actual registration state of `SMAppService.mainApp` instead of trusting only the stored setting for opening at login.

## AppKit bridge

In normal mode, `StatusItemController` owns an `NSStatusItem` and a transient `NSPopover` that hosts the SwiftUI `MenuView`.
It closes the popover in response to local or global mouse input outside the popover, while posture checks continue running.

In debug mode, an `NSHostingController` inside an `NSWindow` wraps the same `MenuView` in a `ScrollView`.
The debug launch flag also enables diagnostic panels and file output through `MenuView`, `AppModel`, and `CameraManager`.
Posture evaluation, settings, and statistics still follow the same paths as normal mode.

## Platform and packaging

The deployment target is macOS 15, and the Swift package declares Swift tools 6.0 as its minimum.
macOS Tahoe 26 and Swift 6.3 are recommended for development, while CI runs on `macos-26` without pinning a separate Swift toolchain.
By default, `package.sh` combines arm64 and x86_64 release binaries into a Universal2 `.app`, applies an ad hoc signature, and creates a ZIP, DMG, and SHA-256 checksums.
For `vMAJOR.MINOR.PATCH` tag releases, `.github/workflows/release.yml` injects the tag version and build number, includes the camera entitlement (`com.apple.security.device.camera`) in the Developer ID signature, requires Apple notarization, and attaches the versioned DMG, ZIP, and SHA-256 checksums to the GitHub Release.
The workflow reads a base64-encoded Developer ID Application P12 from `APPLE_CERTIFICATE`, its password from `APPLE_CERTIFICATE_PASSWORD`, and the notarization account, app-specific password, and team ID from `APPLE_ID`, `APPLE_PASSWORD`, and `APPLE_TEAM_ID` in repository Actions secrets.

The PoseNet and Depth Anything V2 models are included as app resources.
The app itself has no server, listening port, or network request path.
