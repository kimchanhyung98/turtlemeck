# Menu Bar

turtlemeck's main interface is the popover that opens when you click its menu bar icon.
The app has no separate settings window or Dock icon, and posture checks continue after the popover closes.

## Opening and Closing

Clicking the menu bar icon with either mouse button opens the same popover.
There is no separate right-click menu.
Click the icon again or click outside the popover to close it.

## Status Icon

The menu bar icon shows the product's current state.

| State | Icon | Meaning |
|---|---|---|
| Good | 🙂 | Your posture is within the saved baseline range. |
| Poor | 😢 | Poor posture has continued long enough to trigger the poor state. The icon flashes unless Reduce Motion is enabled in macOS. |
| Calibrating | Crosshair | The app is collecting your baseline posture. |
| Waiting or unavailable | 🐢 | The app does not yet have enough posture signals to make a decision. This does not mean your posture is good. |
| Paused | 🫥 | Checks and notifications are paused. |
| Camera needs attention | Slashed camera | The app does not have camera permission or cannot use the camera. |
| Calibration required | Crosshair | No baseline exists, or the saved baseline cannot be used with the current camera and framing, so a new calibration is required. |

When your posture recovers from poor to good, the accessibility label changes to `자세: 회복` (`Posture: Recovered`) for 2 seconds.

## Current Status

The first card in the popover shows the current state, check progress or the time until the next check, and what you need to do.
While waiting for a scheduled check, the message reads `다음 점검 N초 후` (`Next check in N seconds`); it changes to `카메라로 점검 중` (`Checking with camera`) while the camera is active and `점검 분석 중` (`Analyzing check`) during analysis.

If calibration or a camera problem prevents checks from continuing, the same card shows the reason and the next action.
See [Baseline calibration and posture checks](posture-checks.md) for decision rules and recovery steps for each state.

## Quick Actions

| Action | What it does | When unavailable |
|---|---|---|
| **확인 (Check)** | Requests a check without waiting for the scheduled time. If fewer than 15 seconds have passed since the previous camera session began, the check runs after the remaining time. | While paused, when no baseline exists, or when recalibration is required |
| **중지 (Pause)** / **시작 (Resume)** | Pauses or resumes camera checks and posture notifications. | When no baseline exists or recalibration is required |
| **보정 (Calibrate)** | Collects your current upright posture as a new baseline. If a baseline already exists, a successful calibration replaces it. | While paused or when calibration is already in progress |

Checks started with **확인 (Check)** follow the same decision and state transition rules as scheduled checks.
While recalibrating an existing baseline, **확인 (Check)** may appear enabled, but the request is ignored while calibration is in progress.

## Today's Summary

The popover shows these values for the current date.

- **바른 자세 시간 (Good posture time)** — Time spent in the good state
- **주의 자세 시간 (Poor posture time)** — Time spent in the poor state
- **주의 전환 (Poor transitions)** — Number of times the poor state was newly confirmed
- **회복 횟수 (Recoveries)** — Number of transitions from the poor state to the good state
- **보낸 알림 (Notifications sent)** — Number of times the app registered a banner or played the system alert sound

Durations below 1 hour are shown as `N분` (`N minutes`), while durations of 1 hour or more are shown as `N시간 M분` (`N hours M minutes`).
Time spent calibrating, waiting for a decision, paused, or blocked by the camera is excluded from both the good and poor totals.
Statistics are stored locally by date.
See [Privacy and local data](privacy.md#data-stored-on-this-mac) for the storage location and retention behavior.

## Settings and Footer Actions

All settings appear in the same popover rather than in a separate window.
See [Settings](settings.md) for each option.

The following actions appear at the bottom of the popover.

- **카메라 권한 설정 (Camera Permission Settings)** — Opens the Camera privacy pane in macOS System Settings.
- **개인정보 · 비의료 안내 (Privacy · Not Medical Advice)** — Expands or collapses the wellness and privacy guidance in the current popover.
- **종료 (Quit)** — Quits turtlemeck.

Closing the popover is different from choosing **중지 (Pause)** or **종료 (Quit)**.
The app continues running in the menu bar, and scheduled checks and enabled notifications remain active.
