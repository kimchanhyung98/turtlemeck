# Handoff

Last updated: 2026-06-25 18:14 KST

## 1. Current Goal

Project direction changed from hand-written posture heuristics in the product UI to local AI/ML analysis:

- Product-facing analysis methods are ML-only:
  - `AI/ML 자동`
  - `Core ML Depth Anything`
  - `Apple Vision 3D 깊이차`
  - `Apple Vision 3D 신체축`
- Legacy geometry/fusion algorithms remain in code only for internal fallback/regression tests.
- A bundled local Core ML model is now included:
  - `Resources/DepthAnythingV2SmallF16.mlpackage/`
  - `Resources/ThirdPartyNotices.md`

## 2. Important User Context

- User's MacBook is on the right side of the desk.
- User is seated upright during calibration/checks.
- This naturally produces `threeQuarterRight` or sometimes `unknown`, not a stable front view.
- Core ML relative depth is the most useful current signal in this setup.
- Apple Vision 3D works from normal 2D camera frames, but upper-body seated webcam use is intermittent and should remain auxiliary.

## 3. What Was Implemented

### ML Runtime

- Added `CoreMLRelativeDepthProvider`.
  - Loads `DepthAnythingV2SmallF16` from app resources.
  - Runs `VNCoreMLRequest`.
  - Produces `RelativeDepthSummary(headCloserDelta, confidence)`.
  - Can also produce a grayscale depth debug image.

Key file:

- `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift`

### Product ML Selection

- Added `PostureAlgorithmID.mlAuto`.
- Default settings now use `.mlAuto`.
- Saved legacy/non-ML method values migrate to `.mlAuto`.
- Menu picker exposes only `PostureAlgorithmID.userSelectableMLMethods`.
- `AppModel.setPostureAlgorithm` clamps non-ML values to `.mlAuto`.

Key files:

- `Sources/TurtleCore/Detection/Models.swift`
- `Sources/TurtleCore/Storage/Settings.swift`
- `Sources/TurtleCore/App/AppModel.swift`
- `Sources/TurtleCore/MenuBar/MenuView.swift`

### AI/ML Auto

`MLAutoAlgorithm` tries candidates in this order:

1. Core ML relative depth
2. Apple Vision 3D depth delta
3. Apple Vision 3D body-frame axis

The selected/failed candidates are exposed in debug lines as:

`자동 후보  CoreML=... · 3D깊이=... · 3D축=...`

Key file:

- `Sources/TurtleCore/Detection/PostureAlgorithms.swift`

### Calibration

Calibration now stores ML baselines:

- `relativeDepthDelta`
- `depthDeltaNorm`
- `bodyFrameAngle`

For selected ML modes, calibration succeeds only if the required ML baseline exists. This prevents a misleading "calibration succeeded" state where only face/geometric baselines were stored.

Key file:

- `Sources/TurtleCore/Detection/Calibrator.swift`

### Debug Artifacts

In debug mode, each latest burst is written to the project-local folder:

`debug/latest`

Expected files:

- `frame-XX-capture.png`
- `frame-XX-depth.png` when Core ML depth was produced
- `frame-XX-analysis.json`
- `analysis.json`

This folder is ignored by git:

- `.gitignore` includes `debug/`

Debug output is intentionally overwritten each burst; it is not accumulated.

Key files:

- `Sources/TurtleCore/Camera/DebugCaptureStore.swift`
- `Sources/TurtleCore/Camera/CameraManager.swift`
- `.gitignore`

### Run Commands

`make run` keeps its original lighter meaning:

- Run existing `.build/turtlemeck.app`.
- Package only if the app bundle is missing.

New command:

```bash
make fresh-run
```

This:

- quits existing `turtlemeck`
- packages a fresh app
- opens a new instance

Key files:

- `Makefile`
- `scripts/run-app.sh`
- `scripts/fresh-run-app.sh`
- `README.md`

## 4. Latest Observed Runtime Result

The user ran:

1. debug mode
2. recalibration
3. check

Latest inspected `debug/latest/analysis.json` before the final black-frame fix showed:

- `baseline.relativeDepthDelta = -0.17646550364097544`
- `verdict = good`
- `algorithm = mlAuto`
- `observedSignalKinds = ["relativeDepth"]`
- `signalFrameCount = 5`
- `validFrameCount = 5`
- latest value around `-0.161548`
- baseline delta around `+0.015`, below `Tuning.coreMLRelativeDepthForward = 0.08`, so `good` was correct.

Images were also inspected:

- normal capture frames looked valid
- depth frames segmented user/background reasonably
- `frame-01-capture.png` was fully black

That black frame was a camera warmup artifact and was entering analysis.

## 5. Final Fixes Applied After That Runtime Check

After finding the black warmup frame and short effective signal span, the following fixes were added:

- `CameraFrameQuality` skips near-black camera frames before reservation/analysis.
- App-level sampling throttling spreads frames across the burst instead of taking the first dense 30fps frames.
- Burst collection window increased from `2.0s` to `3.0s`.
- Sampling interval set to `0.3s`.
- Added tests:
  - `camera burst timing throttles dense camera frames`
  - `camera frame quality rejects black warmup frames`
- Updated timing tests to the new `3.8s` total capture window and `5.8s` finish delay.

Key file:

- `Sources/TurtleCore/Camera/CameraManager.swift`

## 6. Verification Already Run

Latest verification after final fixes:

```bash
make check
```

Result:

- `101 tests, 101 passed, 0 failed`
- Swift package build passed

```bash
make package
```

Result:

- `.build/turtlemeck.app` generated
- `.build/turtlemeck.zip` generated
- `.build/turtlemeck.dmg` generated
- codesign verification passed inside package script
- universal binary includes `x86_64 arm64`

Final package timestamps seen:

- `.build/turtlemeck.app/Contents/MacOS/turtlemeck`: 2026-06-25 17:59:13 KST
- `.build/turtlemeck.zip`: 2026-06-25 17:59:15 KST
- `.build/turtlemeck.dmg`: 2026-06-25 17:59:16 KST

`git diff --check` passed.

## 7. What The Next Agent Should Do First

Run the new app and collect one fresh debug burst after the final fixes:

```bash
make fresh-run
```

In the app:

1. keep `AI/ML 자동`
2. keep debug mode on
3. run `지금 점검`
4. inspect `debug/latest/analysis.json`

Expected after final fixes:

- no fully black `frame-01-capture.png`
- `frameCount` should be closer to 8 if processing keeps up
- frame timestamps should span roughly 1.8s or more
- `observedSignalKinds` should include `relativeDepth`
- with current calibration, `validFrameCount` should be greater than 0
- verdict should be `good` while user remains upright

If the user recalibrates again, `analysis.json` in calibration mode should contain:

- `mode = "calibration"`
- `calibrationResult = "accepted"` when ML baseline is captured
- `baseline.relativeDepthDelta` in later check runs

## 8. Known Risks / Follow-up Items

1. **Debug files contain camera images.**
   - They are project-local and ignored by git.
   - Do not commit `debug/`.

2. **Core ML depth is relative, not metric.**
   - It should be interpreted only against calibration baseline.
   - Current threshold is `Tuning.coreMLRelativeDepthForward = 0.08`; needs empirical tuning.

3. **Apple Vision 3D is auxiliary.**
   - In seated upper-body webcam views it often has low/no usable signal.
   - Current debug output commonly shows `3D깊이=기준없음` or `신뢰부족`.

4. **Frame timing should be rechecked in live app.**
   - Code now throttles frames, but the final live rerun after this fix has not been inspected yet.
   - This is the most important next verification.

5. **Docs mention earlier timing assumptions.**
   - Some research/todo docs may still mention 2-second burst or 5fps. Update if formal docs need to match final code.

## 9. Files Most Likely Relevant

Runtime:

- `Sources/TurtleCore/Camera/CameraManager.swift`
- `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift`
- `Sources/TurtleCore/Camera/DebugCaptureStore.swift`
- `Sources/TurtleCore/Camera/PoseDetector.swift`

ML logic:

- `Sources/TurtleCore/Detection/Models.swift`
- `Sources/TurtleCore/Detection/PostureAlgorithms.swift`
- `Sources/TurtleCore/Detection/Calibrator.swift`
- `Sources/TurtleCore/Detection/Tuning.swift`
- `Sources/TurtleCore/Detection/BurstProcessor.swift`

UI/settings:

- `Sources/TurtleCore/MenuBar/MenuView.swift`
- `Sources/TurtleCore/App/AppModel.swift`
- `Sources/TurtleCore/Storage/Settings.swift`

Packaging:

- `scripts/package-app.sh`
- `scripts/run-app.sh`
- `scripts/fresh-run-app.sh`
- `Makefile`

Tests:

- `Tests/manual/DetectionTests.swift`
- `Tests/manual/StateTests.swift`
- `Tests/manual/SystemTests.swift`
- `Tests/manual/StorageTests.swift`

Artifacts:

- `Resources/DepthAnythingV2SmallF16.mlpackage/`
- `Resources/ThirdPartyNotices.md`
- `debug/latest/` (ignored)
