# Settings

turtlemeck displays its settings in the **설정 (Settings)** card of the [menu bar popover](menu-bar.md), not in a separate window.
Changes take effect immediately and persist across launches.

## Checks

| Setting | Options | Behavior |
|---|---|---|
| 점검 주기 (Check interval) | 15 / 30 / 60 / 120 / 180 seconds | Sets the interval between the start of routine camera sessions. The default is 60 seconds. When the value changes, the app schedules the next check with the new interval if no capture is in progress. The minimum 15-second gap between session starts also applies to immediate checks requested with **확인 (Check)**. |

There are no user-selectable settings for sensitivity, the decision algorithm, the camera, or resolution.
Every posture decision uses the same relative-depth pipeline and the baseline posture saved by the user.

## Notifications

| Setting | Options | Behavior |
|---|---|---|
| 배너 알림 (Banner notifications) | On / Off | Off by default. Turning this on requests macOS notification permission and registers a Notification Center banner when the poor state is newly confirmed. macOS decides whether to show a permission prompt. |
| 알림 소리 (Notification sound) | On / Off | Off by default. This works independently of banners. If sound is on without banners, the app plays the system alert sound without using Notification Center. |
| 알림 쉬기 (Pause notifications) | 20분 스누즈 (Twenty-Minute Snooze) | Suppresses banners and sounds for 20 minutes. The button is unavailable when both notification settings are off. Snooze resets when the app relaunches. |

See [Notifications](notifications.md) for details about duplicate limits and banner-and-sound combinations.

## General

| Setting | Options | Behavior |
|---|---|---|
| 로그인 시 자동 실행 (Launch at login) | On / Off | Off by default. Registers or unregisters the current app as a macOS login item. On launch, the app shows the actual macOS registration state instead of the saved value. If registration or removal fails, the status card shows `자동 실행 설정 실패` (`Failed to update launch at login`). |

## Storage and Reset

Settings and the baseline posture are stored together under the `com.go.turtlemeck.settings` key in the `com.go.turtlemeck` UserDefaults domain, not in a separate editable file.
An incompatible or invalid baseline, a changed camera configuration, or shoulder framing beyond the stored position or width thresholds is not used and triggers a recalibration request.

The development commands `make run-fresh` and `make run-debug` delete this UserDefaults domain, returning check and notification settings and the baseline posture to their defaults.
They do not remove the macOS login item registration or camera and notification permissions, and daily statistics and existing `debug/` artifacts remain.
See [Debugging](debugging.md#fresh-state-and-debug-runs) for detailed launch behavior.

`--debug` and its related environment variables are not user settings and are not saved.
Developer-facing configuration is documented separately in [Debugging](debugging.md#environment-variables-and-launch-flags).
