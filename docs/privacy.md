# Privacy and Local Data

During normal use, turtlemeck processes camera frames and performs posture analysis on the device.
The app itself does not make network requests, and during normal use it does not save camera images to files or transmit them externally.

## Permissions

| Permission or system feature | When requested | Purpose |
|---|---|---|
| Camera | When a calibration or check first needs the camera while authorization is not determined | Estimates upper-body posture from a short burst of images from the built-in camera. Required for posture checks. |
| Notifications | When the user turns on **배너 알림 (Banner notifications)** | Shows a newly entered poor state as a macOS banner and, depending on settings, plays the default notification sound. Optional. |
| Login item | When the user turns on **로그인 시 자동 실행 (Launch at login)** | Starts the app automatically after the user logs in to macOS. Optional. |

The app does not request microphone access.
Use **카메라 권한 설정 (Camera Permission Settings)** in the popover to change camera access.

## Data Stored on This Mac

| Data | Contents | Location |
|---|---|---|
| Settings and baseline posture | Check interval, notification settings, launch-at-login state, calibration features, and camera and composition information | UserDefaults domain `com.go.turtlemeck` |
| Daily statistics | Date, time in good and poor states, poor transitions, recoveries, and notifications sent | `~/Library/Application Support/turtlemeck/stats.json` |
| Debug artifacts | RGB captures, relative depth images for display, landmark and ROI overlays, and frame and session JSON | `<project-root>/debug/<yyyyMMdd-HHmmss>/` by default |
| Local AI artifacts | Request text and stdout and stderr output from the local process | `<debug-root>/<yyyyMMdd-HHmmss>-local/` |

Daily statistics do not contain images, joint coordinates, depth values, or notification body text.
Daily records and debug sessions have no set retention period and are not deleted automatically.

## Data Not Stored or Transmitted During Normal Use

- Camera RGB frames or video
- Relative depth images
- Joint positions or per-frame decision diagnostics
- External accounts, credentials, or web browsing history

The popover's **개인정보 · 비의료 안내 (Privacy · Not Medical Advice)** section explains this scope and notes that turtlemeck is not a medical device and may detect posture inaccurately.
Consult a medical professional about health concerns or pain.

## Debug and Local Modes

When launched with `--debug` or `TURTLEMECK_DEBUG=1`, the app stores camera RGB images and derived images in the local `debug/` directory for validation.
Setting `TURTLEMECK_LOCAL_AI_EXECUTABLE` also stores the same capture artifacts to create input files for the local process.
Developers must enable these two modes explicitly, and the normal-use statement that images are not stored does not apply to them.

The local AI feature sends a request containing RGB and depth image paths to an external executable selected by the user.
turtlemeck does not restrict that process's network connections or access to additional files.
Review the privacy practices of the tool you plan to use separately.
Local AI results and failures are not fed back into turtlemeck's posture decisions.

See [Debugging](debugging.md#debug-artifacts) for the environment variables and exact file list.

## Development Resets

`make run-fresh` and `make run-debug` reset only the `com.go.turtlemeck` UserDefaults domain that contains settings and the baseline posture.
The macOS login item registration, camera and notification permissions, `stats.json`, and existing `debug/` artifacts remain.
Debug images that contain private information require manual cleanup when they are no longer needed.
