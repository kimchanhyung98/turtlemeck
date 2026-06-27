# Handoff

Last updated: 2026-06-28 00:30 KST

## 1. Current Goal

Project direction changed from hand-written posture heuristics in the product UI to local AI/ML analysis:

- Product-facing manual analysis choices are ML-only:
  - `AI/ML 자동`
  - `Core ML Depth Anything`
  - `Apple Vision 3D 깊이차`
  - `Apple Vision 3D 신체축`
- Legacy geometry/fusion algorithms remain in code for internal fallback/regression tests.
- Non-debug automatic routing is not purely ML-only in the strict implementation sense: side/three-quarter views can still route to `profileGeometry`. Front view now keeps `mlAuto` so Vision 3D can be evaluated when Core ML relative-depth anchors are missing.
- A bundled local Core ML model is now included:
  - `Resources/DepthAnythingV2SmallF16.mlpackage/`
  - `Resources/ThirdPartyNotices.md`

## 2. Important User Context

- User's MacBook is on the right side of the desk.
- User is seated upright during calibration/checks.
- This naturally produces `threeQuarterRight` or sometimes `unknown`, not a stable front view.
- Earlier side/right-desk runs suggested Core ML relative depth was the strongest signal.
- 2026-06-27 front-facing live checks contradicted that assumption on this machine: `VNDetectHumanBodyPoseRequest` 2D returned zero upper-body observations in seated front webcam framing, so Core ML relative-depth anchors could not be built.
- In the same front-facing frames, Apple Vision 3D did return usable `depth3D` / `body3D` signals around confidence 0.70. Treat 3D as a real front-view fallback candidate, not merely an auxiliary/manual path.

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

Important current behavior:

- `ViewpointRouter.route(.front)` now returns `.mlAuto`, not `.coreMLRelativeDepth`, so front routing does not exclude Vision 3D fallback.
- `CoreMLRelativeDepthProvider` now checks `DepthAnchors` before loading the Core ML model. If 2D head/shoulder anchors are unavailable, it returns `nil` without paying the cold model-load cost.

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

## 4. Runtime Results

### Superseded 2026-06-25 side/right-desk result

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

### 2026-06-27 front-facing result

Fresh front-facing runtime checks in `docs/todo/review.md` are now more authoritative for the current work:

- `coreMLRelativeDepth` produced no `relativeDepth` signals in front webcam framing.
- Root cause: Vision 2D body pose returned zero observations for seated close upper-body frames, while face detection and human rectangle detection worked.
- `mlAuto` could produce Vision 3D fallback signals (`depth3D`, sometimes `body3D`) with confidence around 0.70.
- Core ML inference latency after load remained good (~35ms p50 on M1 Max), but process-level model load was ~16s. Before the latest fix, `mlAuto` could trigger this cost even when 2D anchors were missing and Core ML could not produce a usable signal.
- Current stored settings inspected on 2026-06-28: `debugEnabled=true`, `postureAlgorithm=mlAuto`, `baseline.depthDeltaNorm=0.055214207654478736`, `checkIntervalSeconds=30`.

## 5. Fixes Applied After Runtime Checks

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

After the 2026-06-27 front-facing check, the following fixes were also added:

- Front routing now keeps `.mlAuto` instead of forcing `.coreMLRelativeDepth`.
- Core ML relative depth now skips model loading when 2D depth anchors are missing.
- Added tests:
  - `router keeps front on ML auto`
  - `core ml depth provider does not load model without anchors`

Key files:

- `Sources/TurtleCore/Detection/ViewpointRouter.swift`
- `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift`
- `Tests/manual/RoutingTests.swift`
- `Tests/manual/DetectionTests.swift`
- `Tests/manual/TestSupport.swift`

## 6. Verification Already Run

Latest verification after current fixes:

```bash
make check
```

Result:

- `110 tests, 110 passed, 0 failed`
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
- `hdiutil create -format UDZO` failed with `장치가 구성되지 않았음`, but package script fallback `hdiutil makehybrid` succeeded.

Latest package run observed:

- 2026-06-28 00:30 KST

`git diff --check` passed.

## 7. What The Next Agent Should Do First

The remaining missing proof is a fresh GUI app burst after the latest fixes. The last attempts from the Codex shell could not launch the app:

- `open -n .build/turtlemeck.app` failed with `kLSNoExecutableErr`, even though the executable exists, `CFBundleExecutable=turtlemeck`, `codesign --verify` passes, and a minimal test app also failed with the same `open` error.
- Directly running the app binary is not a valid substitute; AppKit aborts during `_RegisterApplication`.
- A temporary headless runner using `CameraManager.runImmediateCheck` reached the camera boundary but failed with `camera permission denied`, because it did not have the GUI app's camera grant.
- Computer Use access to `com.go.turtlemeck` and Finder was denied by MCP elicitation.

Once a GUI launch path is available, run the new app and collect one fresh debug burst:

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
- in front-facing framing, `observedSignalKinds` may be `depth3D` rather than `relativeDepth` if Vision 2D body pose still returns zero observations
- with the current `depthDeltaNorm` baseline, `validFrameCount` should be greater than 0 if Vision 3D fallback is working
- verdict should be `good` while user remains upright; if it is `noEval`, inspect frame reasons before changing thresholds

If the user recalibrates again, `analysis.json` in calibration mode should contain:

- `mode = "calibration"`
- `calibrationResult = "accepted"` when ML baseline is captured
- `baseline.depthDeltaNorm` or `baseline.bodyFrameAngle` in later check runs when front 3D fallback is the live signal

## 8. Known Risks / Follow-up Items

1. **Debug files contain camera images.**
   - They are project-local and ignored by git.
   - Do not commit `debug/`.

2. **Core ML depth is relative, not metric.**
   - It should be interpreted only against calibration baseline.
   - Current threshold is `Tuning.coreMLRelativeDepthForward = 0.08`; needs empirical tuning.

3. **Apple Vision 3D is estimated, not metric sensor truth.**
   - It should remain baseline-relative and quality-gated.
   - Current front-facing evidence shows it can be the only live signal when Vision 2D body pose is empty.

4. **Frame timing and 3D fallback should be rechecked in the GUI app.**
   - Code now throttles frames and skips anchorless Core ML loads, but the final GUI live rerun after this fix has not been inspected yet.
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
