# Baseline Calibration and Posture Checks

turtlemeck does not measure clinically defined angles.
It is a wellness tool that compares current upper-body signals with a baseline posture saved by the user and helps them notice posture habits.

## First Launch

If no baseline posture is saved, the app starts calibration automatically.
If camera access has not yet been decided, macOS asks for access when this calibration first needs the camera.
After granting access, maintain good posture in your usual working position.

If you denied access, use **카메라 권한 설정 (Camera Permission Settings)** in the popover to open System Settings.
Grant access, then select **보정 (Calibrate)** again.
turtlemeck does not provide a camera selector and uses the first available built-in wide-angle camera.

## Calibration

Calibration saves the current posture's relative depth features and variation, camera configuration, and upper-body composition as a single baseline.
Follow these steps to obtain a stable baseline.

1. Settle on your actual working position and screen angle.
2. Sit so your head and both shoulders are visible to the camera.
3. Maintain good posture and remain still. For a manual recalibration, select **보정 (Calibrate)** first.
4. Wait until `기준 자세 저장됨` (`Baseline posture saved`) appears.

Each camera session first uses about 0.8 seconds as a warm-up period.
It then collects up to 5 frames over 2.4 seconds and allows up to 2 additional seconds for in-flight analysis to finish before aggregation.
If the captured burst does not meet the quality and stability conditions, another burst starts 10 seconds after completion, with up to three bursts per calibration.
If the camera does not provide any frames, calibration fails immediately with `카메라 사용 불가` (`Camera unavailable`) without another attempt.

> **Caution:** If you save poor posture as the baseline, even objectively good posture may be classified as poor because it differs from that baseline.
> Routine posture checks never change the baseline automatically; it is replaced only when the user selects **보정 (Calibrate)**.

## Calibration Failures

When calibration fails, routine checks stop until the user selects **보정 (Calibrate)** again.

| Screen status | Meaning | Next step |
|---|---|---|
| 보정 실패: 자세 신호 부족 (Calibration failed: insufficient posture signal) | The app could not obtain stable person, upper-body, or depth signals. | Check the lighting and camera composition, and make sure your head and shoulders are visible. |
| 보정 실패: 자세를 확인할 수 없음 (Calibration failed: posture cannot be assessed) | The head is visible, but tilt, slouching, occlusion, or a similar issue prevents the app from confirming normal posture. | Sit upright again, then recalibrate. |
| 카메라 권한 필요 (Camera permission required) | macOS camera access has not been granted. | Grant access in **카메라 권한 설정 (Camera Permission Settings)**, then recalibrate. |
| 카메라 사용 불가 (Camera unavailable) | The built-in camera could not be opened or did not provide any frames. | Check whether another app is using the camera and whether the device is available, then recalibrate. |

The existing baseline is also not used if the saved camera configuration changes or if shoulder framing moves beyond the stored position or width thresholds.
A sufficient change in camera angle or sitting distance can cause this.
In this case, `보정 필요` (`Calibration required`) appears and routine checks stop until the user recalibrates while maintaining good posture.

## Routine Checks

After calibration, camera sessions start according to the selected [check interval](settings.md#checks).
The interval is measured from the start time of the previous camera session, and each session captures up to 5 frames in the same way as calibration.
The camera does not remain on between checks.

If the display sleeps or macOS interrupts a camera session, any active capture and scheduled check stop.
When the display wakes or the interruption ends, the app schedules the pending calibration, immediate check, or routine check again as appropriate.

## Result of a Single Check

| Result | Meaning |
|---|---|
| Good | Reliable signals are within the saved baseline posture range. |
| Poor | The posture differs enough from the baseline, or most frames show the head but cannot confirm good posture because of the current pose. |
| Unable to evaluate | The app cannot decide because no person is present or the frame, upper-body, depth, or stability signals are insufficient. This result is not treated as good. |

turtlemeck does not enter the poor state after a single poor result.

- From the pending state, one good result changes the status to `자세: 정상` (`Posture: Good`).
- Two consecutive poor results change the status to `자세: 주의` (`Posture: Poor`) and create a notification candidate.
- From the poor state, two consecutive good results restore the status to `자세: 정상` (`Posture: Good`).
- Three consecutive results that combine unable-to-evaluate and borderline outcomes change the status to the pending state, shown as `자세 점검 중` (`Checking posture`).
- An unable-to-evaluate result resets both the poor and recovery streaks and counts toward neither.

See [Notifications](notifications.md) for the conditions that turn a notification candidate into an actual banner or sound.
The technical rationale for the decision sequence and thresholds is documented in the [Posture Analysis Workflow (Korean only)](workflow.md).
