# Notifications

turtlemeck notifies you with a macOS banner or system alert sound when poor posture is confirmed across consecutive checks.
Notifications continue to work while the app is running even when the menu bar popover is closed.

## When Notifications Are Triggered

A notification becomes eligible only when two consecutive [check results](posture-checks.md#result-of-a-single-check) are poor and the app first enters the poor state.
No new notification is sent while the poor state continues or when posture recovers to good.
After recovery, the app returns the product state and menu bar icon to good and increments **회복 횟수 (Recoveries)** in today's summary, but it does not create a recovery notification.

After one poor-posture notification attempt in an app session, at least 25 minutes must pass before another attempt can be made.
The 25-minute limit applies even if banner registration fails.
This limit and the snooze expiration time are kept only in memory and reset when the app relaunches.

## Banners and Sounds

| Banner notifications | Notification sound | Behavior |
|---|---|---|
| Off | Off | Does not send any notification. |
| On | Off | Registers a passive macOS banner without sound. |
| Off | On | Plays the system alert sound without using Notification Center. |
| On | On | Registers a passive macOS banner with the default notification sound. |

Both settings are off by default.
Each time you turn on **배너 알림 (Banner notifications)**, the app requests macOS notification authorization for alerts and sounds.
macOS decides whether to display a permission prompt.
If notifications are not allowed in System Settings, a banner may not appear even when the app requests one.
Sound-only mode does not use notification authorization.

The notification title currently displays the technical identifier `turtlemeck`.
The body cycles through these messages.

- 자세를 한 번 펴볼까요 (How about straightening your posture?)
- 턱을 살짝 당기고 화면을 바라볼까요 (How about gently tucking your chin while looking at the screen?)
- 어깨를 펴고 목을 편하게 세워볼까요 (How about opening your shoulders and keeping your neck comfortably upright?)
- 고개가 앞으로 나왔어요. 등을 펴볼까요 (Your head has moved forward. How about straightening your back?)
- 지금 자세를 한 번 점검해볼 타이밍이에요 (This is a good time to check your posture.)

## 20-Minute Snooze

Selecting **20분 스누즈 (Twenty-Minute Snooze)** in the popover suppresses both banners and sounds for 20 minutes.
Posture checks, state transitions, and today's summary statistics continue during the snooze.
The button is unavailable when both banners and sounds are off.

If the 25-minute repeat limit is still active when the snooze ends, that limit also applies.
Pausing the app stops posture checks themselves, so no notification candidate is created.
A notification skipped because of the snooze or repeat limit is not sent later automatically.
Another qualifying transition into the poor state is required for a new attempt.

## Sent Notification Count

**보낸 알림 (Notifications sent)** counts the times the app either registers a banner request with macOS without an error or plays the system alert sound.
This may differ from the number of banners you actually see because of notification authorization or Focus mode.
