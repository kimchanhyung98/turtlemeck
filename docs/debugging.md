# Debugging

This guide explains how to run a local `turtlemeck` build and inspect the UI state, burst-level posture evaluation, and per-frame intermediate values.
Use it to reproduce camera, calibration, and evaluation issues.

## Requirements

- The app requires macOS 15 or later, and macOS Tahoe 26 or later is recommended.
- Swift tools 6.0 or later are required, and Swift 6.3 or later from Command Line Tools is recommended for development. A full Xcode installation is not required.
- Building the app does not require npm. `package.json` is used only to install Husky Git hooks.

## Checks and local runs

Run all checks from the repository root.

```sh
make check
```

This command verifies the app icon, runs the `workflow-tests` executable tests, and builds the Swift package in sequence.
There is no separate lint command.

To package and run the standard menu bar app:

```sh
make stop
make package
make run
```

`make package` creates `.build/turtlemeck.app`, a ZIP, a DMG, and `SHA256SUMS`.
`make run` packages the app automatically only when the app bundle does not exist.
An already running process does not pick up a new bundle, so use the **stop → package → run** sequence to ensure source changes take effect.

Stop the running app with the following command.

```sh
make stop
```

## Fresh state and debug runs

Run the menu bar app with its first-launch state:

```sh
make run-fresh
```

Run the app in debug-window mode:

```sh
make run-debug
```

> **Data reset:** Both commands stop the running app and delete the `com.go.turtlemeck` UserDefaults domain, removing check and notification settings and the baseline posture.
> They do not remove the macOS login item registration, camera and notification permissions, daily statistics, or existing `debug/` artifacts.

To keep the settings and baseline posture while opening only the debug window, package the app first and pass the flag directly.

```sh
make package
open -n .build/turtlemeck.app --args --debug
```

Debug mode opens a 600×680 standard window titled `turtlemeck` instead of the menu bar icon, and adds the **분석 (Analysis)** and **디버그 (Debug)** panels to the shared interface.
The window is resizable and its content scrolls.

## Debug interface

Before the first measurement, the interface displays `아직 측정 데이터 없음 (점검 대기)` (“No measurement data yet (waiting for check)”).
After a check, it adds the following information.

- The result of one burst and the product state after persistence is applied
- Total and valid frame counts, feature medians and MADs, baseline centers, and differences
- Counts by exclusion reason, plus per-frame features or exclusion reasons
- Landmarks, head, torso, and reference ROIs, relative depth, and quality values
- Processing times for PoseNet, Depth Anything V2, feature extraction, burst aggregation, and state transitions
- Current baseline posture summary, check interval, and debug output path

When an artifact path is available, **디버그 폴더 열기 (Open Debug Folder)** opens that session directory in Finder.
Some internal evidence and failure reasons appear as their raw English values from the code.

## Debug artifacts

The default output root is `debug/`, created after locating the project root from the source, app bundle, executable, or current directory.
Each camera session uses the following structure.

```text
debug/<yyyyMMdd-HHmmss>/
├── capture-<n>.png
├── overlay-<n>.png
├── depth-<n>.png
├── frame-<n>.json
└── session.json
```

`capture` is the RGB frame, `overlay` shows landmarks and ROIs, and `depth` is the relative-depth visualization.
The frame JSON contains features, quality values, and exclusion reasons, while `session.json` contains the raw burst result, product state, baseline posture, and processing times.
Some frames may omit images after a quality failure.

These files can contain the user's image and are not deleted automatically.
For details about the privacy boundary, see [Privacy and local data](privacy.md#debug-and-local-modes).

## Environment variables and launch flags

| Item | Activation | Behavior |
|---|---|---|
| `--debug` | Included in launch arguments | Enables window mode, the debug interface, and file output. |
| `TURTLEMECK_DEBUG` | Value is exactly `1` | Behaves like `--debug`. The value is not persisted. |
| `TURTLEMECK_DEBUG_ROOT` | Absolute path beginning with `/` | Writes output to this path instead of the automatically discovered project `debug/` directory. Relative paths are ignored. |
| `TURTLEMECK_LOCAL_AI_EXECUTABLE` | Absolute executable path beginning with `/` | Creates the shared RGB and depth artifacts, then passes matching image pairs to a local process. Images are saved even without the debug flag. |
| `TURTLEMECK_LOCAL_AI_ARGUMENTS_JSON` | JSON string array | Provides arguments for the local executable. A missing or invalid value uses an empty array. |

To ensure the environment variables are passed through, run the packaged executable directly from the terminal.

```sh
TURTLEMECK_DEBUG=1 \
TURTLEMECK_DEBUG_ROOT=/absolute/path/to/debug \
.build/turtlemeck.app/Contents/MacOS/turtlemeck
```

The repository does not load `.env` files automatically.

When local AI is enabled and at least one matching RGB and depth image pair exists, the app creates the following files next to the shared session.

```text
debug/<yyyyMMdd-HHmmss>-local/
├── request.md
└── analysis.md
```

`request.md` contains the absolute paths of matching RGB and depth files.
The local process receives the prompt through standard input and writes both stdout and stderr to `analysis.md`.
Execution failures and output content do not affect `turtlemeck`'s posture evaluation.

## Analyzing saved images

Use the following tool to analyze saved images without running the camera lifecycle.

```sh
swift run --disable-sandbox analyze-image <image-path> [image-path ...]
```

The tool writes each image's validity, features, exclusion reason, and landmark geometry to standard output.
It does not modify the input files.

## Troubleshooting

- **Source changes do not appear in the app.** Run `make stop && make package && make run` to replace the running process as well as the bundle.
- **Camera permission is required.** Allow access from **카메라 권한 설정 (Camera Permission Settings)** in the popover, then recalibrate while sitting upright.
- **Calibration keeps failing.** Check that the head and both shoulders are visible, verify the lighting and camera framing, and remain still during calibration.
- **No debug files are created.** Check the debug flag. If the app is installed where the project root cannot be discovered automatically, set `TURTLEMECK_DEBUG_ROOT` to an absolute path.
- **Notifications do not repeat.** Check whether this is a new transition into the poor state and whether the 20-minute snooze or 25-minute minimum interval is still active.

`turtlemeck` does not currently create rotating text log files.
Use the debug interface and frame and session JSON files to investigate evaluation issues.
