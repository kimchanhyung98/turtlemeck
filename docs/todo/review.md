# Review

Last updated: 2026-06-28 00:30 KST

## Scope

검토 대상:

- `docs/todo/handoff.md`
- `docs/algorithm/**`
- `docs/depth-estimation/**`
- `docs/todo/local-llm-ai-cli-plan.md`
- `docs/todo/viewpoint-auto-workflow.md`
- 현재 코드/테스트/패키징 상태

2026-06-27 23:30 KST까지의 내용은 리뷰/실측 기록이고, 23:53 KST 이후에는 그 리뷰를 바탕으로 일부 코드 개선을 적용했다. 명확한 불일치, 배포 전 리스크, 반영한 개선 사항을 아래에 기록한다.

## Executive Summary

현재 상태는 **빌드/패키징은 가능하지만, 정면 라이브 환경에서 기본 제품 경로(Core ML 상대깊이)가 신호를 전혀 만들지 못해 배포 불가**다.

2026-06-27 정면 실측(아래 "Local Runtime Verification")에서 드러난 핵심:

- **기본 경로가 죽어 있다.** 정면 웹캠 라이브에서 `coreMLRelativeDepth`(및 모든 2D 기하 경로)는 머리·어깨 앵커를 2D 신체 포즈에서 만드는데, 이 머신(macOS 26.5.1)에서 **`VNDetectHumanBodyPoseRequest`(2D)가 앉은 상체 프레임에 대해 관측을 0개 반환**한다. 그 결과 `relativeDepth`가 영구 nil(`Core ML 상대깊이 없음`)이고, ~75초/다수 버스트 동안 verdict가 계속 `noEval`이었다. 얼굴 감지·사람 사각형(conf 0.68~0.72)은 같은 프레임에서 정상 동작한다.
- **3D가 오히려 살아 있다.** 같은 라이브 프레임에서 `VNDetectHumanBodyPose3DRequest`(3D)는 결과를 반환하며, `depthDelta`/`bodyFrame3D`/`mlAuto`는 `depth3D`/`body3D` 신호를 **confidence 0.70**으로 만든다(라이브 자동 버스트에서 8프레임 중 2~6프레임 신호). 이는 handoff/review가 전제한 "3D는 보조·웹캠 confidence 0.5 미만"과 `ViewpointRouter`의 "3D 제외" 근거를 **정면으로 뒤집는다.**
- **성능(Core ML)은 레퍼런스에 부합.** 번들 `DepthAnythingV2SmallF16`의 정상 추론 지연은 M1 Max에서 **p50 ≈ 34.9ms**(min 31.5, p90 35.6)로 HF 카드값(M1 Max 32.80ms)과 일치. 다만 **프로세스당 모델 로드가 ~16초**(2회 측정 동일, 교차프로세스 캐시 미적중) + 첫 추론 워밍업 ~1.4초가 있어 **앱 첫 버스트는 항상 frames=0**(모델 로드가 버스트를 소진)으로 관측됐다.
- 빌드/검사: 이번 세션은 `make package`(통과) 재실행 + 라이브 검증 중심. `make check`(`109 tests passed`)는 2026-06-26 기록. 번들 모델은 무결(번들 경로에서 직접 로드·추론 정상).

요약: 코드/패키징/모델은 정상이지만, **제품 기본 경로의 입력원(2D 신체 포즈)이 이 OS·프레이밍에서 비어 있어 정면 판정이 불가능**하다. 단기적으로 동작 가능한 유일한 라이브 경로는 3D 기반(mlAuto의 3D 폴백)이다.

## Local Runtime Verification (정면 실측, 2026-06-27)

환경: MacBook Pro **Apple M1 Max / 64GB / macOS 26.5.1 (25F80)**, 내장 카메라 정면, 사용자 정자세. 빌드는 `make package`(universal), 설정은 디버그 모드 + 점검주기 10초로 주입해 자동 버스트 산출물(`debug/latest`)을 검사했다. 사용자가 카메라 권한을 허용했고 캡처/얼굴 인식은 정상이었다.

### 1. 기본 경로(`coreMLRelativeDepth`)는 정면 라이브에서 신호 0

- `debugEnabled=true`, `postureAlgorithm=coreMLRelativeDepth`, 10초 주기로 실행. ~75초/다수 버스트 동안 매 버스트가 `frames=8, captures=8`이지만 `depths=0, observedSignalKinds=[], validFrameCount=0, verdict=noEval`.
- 프레임별 reason은 일관되게 `Core ML 상대깊이 없음`, viewpoint는 `front`(얼굴 박스 기반).
- 캡처 PNG는 머리·양 어깨가 정상적으로 보이는 평범한 상체 정면 샷이었다(프레이밍 문제 아님).

### 2. 근본 원인: 2D 신체 포즈가 빈 결과

- 캡처 프레임을 `analyze-image`(앱과 동일한 `PoseDetector`)로 분석하면 **모든 신체 랜드마크가 nil**(`nose=— … lSh=— rSh=—`), 얼굴 박스만 존재.
- 원시 Vision 진단(독립 스크립트)으로 동일 프레임을 검사:
  - `VNDetectHumanBodyPoseRequest`(2D): `perform` 성공, **results=0** (에러 없이 0개, supportedRevisions=[1]).
  - `VNDetectFaceLandmarksRequest`: 1개, `VNDetectHumanRectanglesRequest`: 1개(conf 0.68~0.72) — 사람 자체는 감지됨.
  - `VNDetectHumanBodyPose3DRequest`(3D): **results=1**.
- 교차 검증: 깨끗한 인물 포트레이트도 2D=0, 그러나 선명한 전신 이미지는 2D=1. → **2D 신체 포즈가 "앉은 상체·근접·저각도 웹캠" 프레이밍에서 실패**하는 것이며 API 전면 고장은 아니다. 문제는 앱이 동작해야 하는 바로 그 프레이밍에서 비어 있다는 점.
- 함의: `coreMLRelativeDepth`의 `DepthAnchors`(머리=코/눈/귀, 어깨=양 어깨/목)와 모든 2D 기하 신호(`profile2D`/`front2D`)의 입력이 사라져 영구 noEval. 인수인계 §4의 "동작했던 `relativeDepthDelta=-0.176`"은 이 OS/정면 프레이밍에서 재현되지 않는다(다른 OS/배치였을 것).

### 3. 3D 경로는 라이브로 신호 산출 (문서 전제와 반대)

- `postureAlgorithm=mlAuto`로 재실행. CoreML 후보는 매 프레임 `신호없음`이나 **3D 깊이로 폴백**해 신호를 만든다.
- 대표 버스트(자동, 정면): `observedSignalKinds=['depth3D']`, **8프레임 중 6프레임** `depth3D` conf **0.70**, value ≈ 0.057(대표값), viewpoint=front. 나머지 2프레임은 `3D깊이=신뢰부족`(간헐성 존재).
- 디버그 라인 예: `자동 후보  CoreML=신호없음 · 3D깊이=선택 · 3D축=기준없음`.
- `analyze-image`로 같은 프레임 단발 검증: `depthDelta` → `depth3D conf 0.70`, `bodyFrame3D` → `body3D 87.2° conf 0.70`, 둘 다 `baseline 필요(보정)`만 남음.
- 따라서 `ViewpointRouter`의 "3D는 웹캠 confidence 0.5 미만이라 자동 라우팅 제외"라는 주석과 review의 "3D는 보조" 전제는 **이 정면 실측과 반대**다. 정면에서 confidence 게이트(0.5)를 넘긴 것은 2D Core ML이 아니라 3D였다.
- 주의: `PoseDetector.point3D`의 per-joint confidence는 0.9로 하드코딩이고, 신호 confidence 0.70은 파생값이다. 절대 신뢰도로 해석하면 안 되지만, 파이프라인 게이트를 통과해 신호를 산출한다는 사실은 변하지 않는다.

### 4. Core ML 모델 성능 (M1 Max)

번들 `DepthAnythingV2SmallF16.mlpackage`를 앱과 동일 경로(`MLModel.compileModel` → `MLModel(.all)` → `VNCoreMLModel` → `VNCoreMLRequest(scaleFill)`)로 독립 측정:

| 항목 | 값 |
|---|---|
| 입력/출력 | image 518×392 → depth |
| compile(mlpackage→mlmodelc) | ~0.17s |
| **모델 load(.all)** | **~15.8~15.9s** (2회 동일, 교차프로세스 캐시 미적중) |
| 첫 추론 워밍업 | 1.36s(콜드) → 0.07s(2회차) |
| **정상 추론 지연** | **p50 34.9ms, mean 34.5ms, min 31.5, p90 35.6** |

- 정상 추론 지연은 HF 카드(M1 Max 32.80ms)와 부합 → 성능 주장은 타당.
- 단, **프로세스당 ~16초 모델 load** 비용이 커서 앱 첫 버스트는 항상 `frames=0`(로드가 버스트 창 5.8s를 초과해 첫 버스트 프레임 전부 드롭)으로 관측됐다. `coreMLRelativeDepth`/`mlAuto` 모두 동일. mlAuto는 2D 앵커가 없어 Core ML을 못 쓰면서도 매 프레임 Core ML을 호출해 이 16초 로드를 유발한다(낭비).
- 번들된 mlpackage는 `cp -R`+`codesign --deep` 후에도 무결(번들 경로에서 직접 로드·추론 정상) — 패키징이 모델을 손상시키지 않는다.

### 5. 미실행 항목

- **3D 폴백의 보정→good/bad 엔드투엔드**: 재보정은 메뉴 클릭(사용자 물리 조작)이 필요해 이번 세션에서 라이브로 완결하지 못했다. 단 보정 임계(depth3D=0.5)를 넘는 프레임이 버스트당 다수(6/8, conf 0.70) 관측되므로 재보정은 성공해 `depthDeltaNorm` baseline을 잡을 것으로 보인다(코드·신호상 정합). 실제 verdict 산출 확인은 다음 라이브 단계로 남긴다.

## Research Verification

### Apple Vision / macOS Depth

검증 결과: **타당함.**

- `AVCaptureDepthDataOutput`은 Apple 문서상 compatible camera devices용이며 플랫폼 목록에 네이티브 macOS가 없다. iOS/iPadOS/Mac Catalyst/tvOS만 표시된다.  
  Source: <https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput>
- ARKit도 네이티브 macOS 대상이 아니며 hardware sensing 전제다.  
  Source: <https://developer.apple.com/documentation/arkit>
- `VNGeneratePersonInstanceMaskRequest`는 macOS 14.0+로 확인된다.  
  Source: <https://developer.apple.com/documentation/vision/vngeneratepersoninstancemaskrequest>
- `VNCoreMLRequest`는 macOS 10.13+에서 Core ML image-analysis request로 쓰는 경로가 맞다.  
  Source: <https://developer.apple.com/documentation/vision/vncoremlrequest/model>

따라서 "MacBook 단일 RGB 웹캠에는 하드웨어 depth가 없고, 현실적인 경로는 Core ML monocular depth"라는 문서 결론은 적절하다.

### Apple Vision 3D

검증 결과: **타당하되 제품 신호로는 보수적 취급이 맞음.**

Apple WWDC23 자료는 `VNDetectHumanBodyPose3DRequest`가 이미지에서 17개 3D joint skeleton을 반환하고, 3D joint position은 hip/root 기준 meter 좌표라고 설명한다. 또한 "without ARKit or ARSession"이라고 설명하므로, 단일 2D 이미지/프레임에서 Vision 3D 추정이 가능하다는 문서 결론은 맞다.  
Source: <https://developer.apple.com/videos/play/wwdc2023/111241/>

다만 이는 실제 metric 센서 측정이 아니라 Vision 추정값이다. 현재 코드가 3D를 보조 후보로 두고 baseline/quality gate를 요구하는 방향은 리서치와 맞다.

### Depth Anything V2 / Core ML

검증 결과: **타당함.**

- Apple/Hugging Face `apple/coreml-depth-anything-v2-small`은 Apache-2.0, F16 49.8MB, M1 Max 32.80ms, M3 Max 24.58ms, dominant compute unit Neural Engine으로 표시된다.  
  Source: <https://huggingface.co/apple/coreml-depth-anything-v2-small>
- Depth Anything V2 upstream은 Small 24.8M, Base 97.5M, Large 335.3M, Giant 1.3B coming soon으로 표시하고, Small은 Apache-2.0, Base/Large/Giant는 CC-BY-NC-4.0이라고 명시한다.  
  Source: <https://github.com/DepthAnything/Depth-Anything-V2>

따라서 제품 후보를 `DepthAnythingV2SmallF16.mlpackage` 하나로 고정한 것은 배포/라이선스/성능 관점에서 적절하다.

### Apple Depth Pro

검증 결과: **제품 제외 결론은 타당. 단, 라이선스 설명은 더 정밀해야 함.**

- Hugging Face `apple/DepthPro`의 LICENSE는 `Research Purposes` 전용이며 상업적 이용, 제품 개발, 상용 제품/서비스 사용을 제외한다고 명시한다.  
  Source: <https://huggingface.co/apple/DepthPro/blob/main/LICENSE>
- `apple/DepthPro-hf` 모델 카드에는 상단 license tag가 `apple-amlr`, card 내부에는 `Apple-ASCL` 표기도 함께 보여 혼선이 있다.  
  Source: <https://huggingface.co/apple/DepthPro-hf>
- GitHub `apple/ml-depth-pro`는 reference implementation과 model weights가 repo `LICENSE` terms라고 적고, 해당 GitHub LICENSE는 Apple sample-code 계열 문구다.  
  Sources: <https://github.com/apple/ml-depth-pro>, <https://github.com/apple/ml-depth-pro/blob/main/LICENSE>

정리: 문서의 "Depth Pro는 제품 후보에서 제외" 결론은 보수적으로 맞다. 다만 "Depth Pro 전체가 단일하게 apple-amlr research-only"라고만 쓰면 GitHub repo와 HF repo의 표기 차이를 설명하지 못한다. 리뷰 이후 문서 정리 시 "HF `apple/DepthPro` weights는 research-only이며, GitHub/HF 표기 차이가 있어 별도 Apple 허가/법무 확인 전 제품 제외"로 정밀화하는 편이 맞다.

### FHP / CVA / 단안 한계

검증 결과: **타당함.**

- CVA cutoff는 연구마다 다르며 normal/FHP/severe 범위가 혼재한다고 최신 논문이 명시한다.  
  Source: <https://pmc.ncbi.nlm.nih.gov/articles/PMC11042887/>
- JMIR 2024 e55476은 2D RGB 입력에서 3D pose estimation과 GCN으로 FHP를 학습할 수 있음을 보이지만, shoulder-angle 단독 분포가 겹쳐 구분이 어렵다는 Figure 설명을 제공한다.  
  Source: <https://formative.jmir.org/2024/1/e55476>

따라서 "절대 임계 하나로 진단하지 말고, baseline 상대 신호와 보수적 noEval을 사용"한다는 리서치 방향은 적절하다.

## Plan Review

### `local-llm-ai-cli-plan.md`

대체로 적절하다.

- 앱 런타임과 개발자용 AI CLI를 분리한다는 결정은 맞다.
- Hugging Face CLI/Python 의존성을 제품 런타임에 넣지 않는 결정도 맞다.
- `codex exec --image`, `--oss`, `--local-provider ollama`는 현재 로컬 `codex exec --help`에서도 확인된다.
- `codex -p`가 prompt가 아니라 profile 옵션이라는 주의도 현재 `codex-cli 0.142.2` 기준 맞다.
- `claude -p/--print`는 현재 `claude 2.1.193` 및 공식 Claude Code CLI reference 기준 맞다.  
  Source: <https://code.claude.com/docs/en/cli-reference>
- `hf` CLI 설치/다운로드 경로는 Hugging Face 공식 문서와 맞다.  
  Sources: <https://huggingface.co/docs/huggingface_hub/en/installation>, <https://huggingface.co/docs/huggingface_hub/en/guides/cli>

문서의 stale 항목:

- 로컬 버전은 문서의 `codex-cli 0.142.0`, `claude 2.1.191`에서 현재 `codex-cli 0.142.2`, `claude 2.1.193`으로 바뀌었다.
- `scripts/run-tests.sh` 결과는 문서의 `97 tests passed`가 아니라 현재 `110 tests passed`다.
- `hf`, `huggingface-cli`는 현재도 PATH에 없음. `ollama`는 `/opt/homebrew/bin/ollama`에 있음.

### `viewpoint-auto-workflow.md`

부분적으로 적절하나, 기존 "ML-only" 방향과 충돌한다.

적절한 점:

- 정면은 `coreMLRelativeDepth`, 측면/3-4는 `profileGeometry`, `unknown`은 직전 유지라는 설계는 현재 사용자 배치(맥북 오른쪽, 사용자 정자세)와 로컬 실측에 맞는 실용적 개선이다.
- 히스테리시스 K=2 설계와 라우팅 테스트는 구현되어 있다.

충돌/리스크:

- `docs/todo/handoff.md`는 product-facing analysis methods를 ML-only로 설명한다.
- 현재 `ViewpointRouter`는 측면/3-4를 `profileGeometry`로 라우팅한다.
- `MenuView`는 디버그 off일 때 "자동 (시점 인식)"으로 표시하고 "정면=깊이 · 측면/3-4=2D 시상 기하"라고 설명한다. 즉 제품 동작은 더 이상 순수 ML-only가 아니다.

이 선택은 기술적으로 방어 가능하지만, 제품 방향 문서와 명확히 합의되어야 한다. "알고리즘 안 쓰고 ML 처리"가 여전히 최상위 요구라면 현재 라우팅 설계는 되돌리거나 ML-only 라우팅으로 바꿔야 한다.

**2026-06-27 정면 실측으로 라우팅 근거 일부가 반증됨**: `ViewpointRouter`/문서의 핵심 가정은 "정면=`coreMLRelativeDepth`가 동작, 3D는 confidence 0.5 미만이라 제외"였다. 그러나 정면 라이브에서 (1) `coreMLRelativeDepth`는 2D 신체 포즈 부재로 신호 0, (2) 3D(`depth3D`)는 confidence 0.70으로 6/8 프레임 신호를 냈다. 즉 정면에서 confidence 게이트를 통과한 것은 3D였다. 라우팅 표(정면→Core ML)는 이 OS·웹캠 프레이밍에서 입력이 없는 경로를 가리키므로, 정면 매핑을 3D 폴백 우선으로 재검토해야 한다. (라우터의 2D 신체 포즈 의존 자체가 빈 입력이라 정면 분류도 얼굴 박스에만 의존하게 된다.)

## Code Review

### 구현된 항목

- Core ML depth provider 존재:
  - `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift`
  - `VNCoreMLRequest` 실행, pixelBuffer/multiArray 결과 처리, debug depth image 생성, Float16 decode 구현.
- Core ML depth signal/baseline 존재:
  - `SignalKind.relativeDepth`
  - `Baseline.relativeDepthDelta`
  - `Calibrator`가 `relativeDepthDelta`, `depthDeltaNorm`, `bodyFrameAngle` 저장.
- ML 선택지 존재:
  - `PostureAlgorithmID.userSelectableMLMethods = [.mlAuto, .coreMLRelativeDepth, .depthDelta, .bodyFrame3D]`.
- debug-only 수동 선택 확장:
  - `debugSelectableMethods = userSelectableMLMethods + [.profileGeometry, .frontProxy]`.
- 디버그 artifact:
  - `DebugCaptureStore`가 `debug/latest`에 capture/depth/analysis JSON을 기록.
- 패키징:
  - `scripts/package-app.sh`가 `DepthAnythingV2SmallF16.{mlmodelc,mlpackage,mlmodel}`와 `ThirdPartyNotices.md`를 앱 번들에 복사.

### 주요 불일치

1. **인수인계 문서의 ML-only 설명과 현재 코드가 다름.**

   - 문서: saved legacy/non-ML은 `.mlAuto`로 migration, picker는 `userSelectableMLMethods`만 노출.
   - 코드: `Settings` decode는 `debugSelectableMethods`를 허용한다. 즉 `profileGeometry`/`frontProxy`는 저장값으로 살아남을 수 있다.
   - 코드: 디버그 off에서는 `settings.postureAlgorithm`이 아니라 `routedAlgorithm`을 사용하며, 라우터는 측면/3-4를 `profileGeometry`로 선택한다.

2. **디버그/진단에 effective algorithm이 명확히 기록되지 않는다.**

   - `DebugCaptureStore.writeFinalAnalysis`는 `algorithm: settings.postureAlgorithm`을 저장한다.
   - 디버그 off에서는 artifact를 쓰지 않으므로 큰 문제는 아니지만, 자동 라우팅 검증을 하려면 `settings.postureAlgorithm`과 `effectiveAlgorithm`을 분리 기록하는 편이 낫다.

3. **라우팅 전환과 보정 baseline 요구 타이밍이 까다롭다.**

   - `finishBurst`에서 frames를 처리한 뒤 `routeSelector.update(...)`로 `routedAlgorithm`을 갱신하고, 바로 `Calibrator.capture(... requiredAlgorithm: effectiveAlgorithm())`를 호출한다.
   - 시점이 바뀐 첫 보정 burst에서 frames는 이전 effective algorithm으로 생성됐을 수 있는데, required baseline은 갱신된 algorithm 기준이 될 수 있다.
   - 실제 사용에서는 "시점 변경 후 한두 번 check가 지나 라우팅이 안정된 뒤 재보정"하면 피할 수 있지만, UX상 바로 재보정하면 실패할 가능성이 있다.

4. **오래된 주석/문서가 남아 있다.**

   - `CameraManager` 주석은 "동일한 2초 버스트"라고 하지만 현재 `CameraBurstTiming.collectionSeconds = 3.0`, total `3.8`, finish `5.8`이다.
   - `docs/todo/README.md`, `local-llm-ai-cli-plan.md`에는 `97 tests`가 남아 있다.

5. **(2026-06-27 갱신) fresh run을 수행했고, 더 근본적인 문제를 확인함.**

   - `Core ML Depth Anything`/`AI/ML 자동`으로 fresh run + 디버그 점검을 다시 실행한 결과는 위 "Local Runtime Verification"에 정리.
   - 결론: `relativeDepth`가 안 나오는 직접 원인은 baseline 부재가 아니라 **2D 신체 포즈(`VNDetectHumanBodyPoseRequest`)가 정면 상체 웹캠 프레임에서 빈 결과**라는 점. 따라서 Core ML 깊이 앵커가 구성되지 않는다.

6. **mlAuto가 사용 불가능한 Core ML을 매 프레임 호출해 ~16초 모델 로드를 유발.**

   - 정면에서 2D 앵커가 없어 Core ML 후보는 항상 `신호없음`인데도, `mlAuto`는 후보 순서상 Core ML을 먼저 호출한다. 첫 호출에서 `MLModel.compileModel`+load(~16s)를 동기 수행 → 앱 첫 버스트가 통째로 드롭(frames=0).
   - 개선안: (a) 2D 앵커 부재 시 Core ML 호출 자체를 건너뛰기, (b) 모델을 앱 시작 시 백그라운드 선로딩(첫 버스트 지연 제거), (c) 가능하면 mlpackage 대신 사전 컴파일된 `.mlmodelc`를 번들해 compile 단계 제거(로드 비용 자체는 별개).

7. **첫 버스트 무효 + 모델 로드 타이밍.**

   - `CameraBurstTiming.finishDelay = 5.8s`인데 콜드 모델 로드가 ~16s라, 모델을 처음 쓰는 버스트의 모든 프레임이 finishDelay를 초과해 드롭된다(실측: coreMLRelativeDepth/mlAuto 모두 첫 버스트 frames=0). 사용자가 실행 직후 점검/재보정을 누르면 첫 시도가 조용히 실패할 수 있다.

### 2026-06-27 23:53 KST 반영한 개선

1. **정면 라우팅을 Core ML 단독에서 `mlAuto` 유지로 변경.**

   - 변경: `ViewpointRouter.route(.front)`가 `.coreMLRelativeDepth` 대신 `.mlAuto`를 반환한다.
   - 의도: 정면에서 2D body pose가 비어 Core ML 상대깊이 앵커를 만들 수 없을 때도 Vision 3D fallback(`depth3D`/`body3D`)을 함께 평가한다.
   - 범위: 측면/3-4의 `profileGeometry` 라우팅은 이번 변경에서 건드리지 않았다.

2. **2D 깊이 앵커가 없으면 Core ML 모델을 로드하지 않도록 변경.**

   - 변경: `CoreMLRelativeDepthProvider`가 `DepthAnchors`를 먼저 구성하고, 앵커가 있을 때만 `visionModel()`을 호출한다.
   - 의도: 정면 실측처럼 2D body pose가 빈 프레임에서 `mlAuto`가 사용 불가능한 Core ML 후보 때문에 ~16초 모델 로드를 유발하지 않도록 한다.
   - 한계: 2D 앵커가 있는 첫 Core ML 사용 시의 콜드 모델 로드 비용 자체는 남아 있다. 백그라운드 선로딩 또는 사전 컴파일 `.mlmodelc` 번들링은 별도 개선 항목이다.

## Verification Run

실행한 검증:

> 출처 주석: 아래 첫 `make check`(109 tests)는 2026-06-26 이전 리뷰 기록이다. **2026-06-28 00:30 KST 현재 상태에서는 `make check`를 재실행해 110개 테스트와 Swift build 통과를 확인했고, `make package`도 재실행해 통과를 확인했다.** 개선 후 `make fresh-run`은 패키징까지 성공했지만 CLI `open` 단계가 `kLSNoExecutableErr`로 실패해 새 라이브 burst는 확보하지 못했다.

```bash
make check
```

결과(2026-06-26):

- `109 tests, 109 passed, 0 failed`
- Swift package build passed
- SwiftPM user cache/write warning과 missing `CLAUDE.md` exclude warning은 있었지만 실패는 아님.

```bash
scripts/run-tests.sh
```

결과(2026-06-28 00:30 KST, 개선 후):

- `110 tests, 110 passed, 0 failed`
- Swift package build passed
- 추가된 회귀 테스트:
  - `router keeps front on ML auto`
  - `core ml depth provider does not load model without anchors`

```bash
make package
```

결과:

- `.build/turtlemeck.app` 생성
- `.build/turtlemeck.zip` 생성
- `.build/turtlemeck.dmg` 생성
- `codesign --verify --deep --strict --verbose=2 .build/turtlemeck.app` 통과
- universal binary: `x86_64 arm64`
- 2026-06-28 00:30 KST 재실행도 통과. `hdiutil create -format UDZO`는 `장치가 구성되지 않았음`으로 실패했지만, 스크립트의 `hdiutil makehybrid` fallback이 성공해 DMG는 생성됨.

```bash
git diff --check
```

결과:

- 통과.

번들 확인:

- `.build/turtlemeck.app/Contents/Resources/DepthAnythingV2SmallF16.mlpackage` 존재
- `.build/turtlemeck.app/Contents/Resources/ThirdPartyNotices.md` 존재
- `.build/turtlemeck.zip`: 44MB
- `.build/turtlemeck.dmg`: 50MB

개선 후 실행 시도:

```bash
make fresh-run
```

결과(2026-06-27 23:54 KST):

- `swift build --disable-sandbox -c release --arch arm64 --product turtlemeck` 통과
- `swift build --disable-sandbox -c release --arch x86_64 --product turtlemeck` 통과
- `codesign --verify --deep --strict --verbose=2 .build/turtlemeck.app` 통과
- universal binary `x86_64 arm64` 확인
- ZIP/DMG 생성 완료(`hdiutil create` 실패 후 `makehybrid` fallback 성공)
- 마지막 `open -n .build/turtlemeck.app` 단계는 `kLSNoExecutableErr: The executable is missing`으로 실패

추가 분리 확인:

- `.build/turtlemeck.app/Contents/MacOS/turtlemeck`는 존재하고 실행 권한이 있으며, `file`은 Mach-O universal binary로 확인.
- `Info.plist`의 `CFBundleExecutable=turtlemeck`, `codesign --verify` 모두 정상.
- `/private/tmp`에 복사한 동일 번들 및 리소스를 제거한 최소 번들도 `open`에서 같은 `kLSNoExecutableErr`가 발생.
- 임시로 만든 최소 테스트 앱도 같은 `open` 오류가 발생해, 이번 CLI 세션의 LaunchServices/open 경로 제약 가능성이 높다.
- 앱 바이너리 직접 실행은 AppKit `_RegisterApplication` 단계에서 `SIGABRT`(exit 134)로 종료되어 올바른 검증 경로가 아니다.
- Computer Use의 `com.go.turtlemeck` 접근은 MCP elicitation에서 거부되어 UI 검증을 이어가지 못했다.
- 2026-06-28 00:05 KST 추가 확인: 같은 `TurtleCore`의 `CameraManager.runImmediateCheck`를 호출하는 임시 headless 실행기를 컴파일해 실행했다. 일반 CLI 바이너리와 `com.go.turtlemeck` bundle id/Info.plist를 가진 임시 headless `.app` 직접 실행 모두 `BLOCKED camera permission denied`로 종료됐다. 즉 현재 세션에서 UI 앱은 LaunchServices/open, headless 직접 실행은 TCC 카메라 권한에서 각각 막힌다. 이 headless 시도는 제품 앱 라이브 검증을 대체하지 못한다.

## Deployment Gate

현재 상태에서 배포 전 필요한 확인:

1. **제품 방향 확정**
   - 선택 A: "ML-only"를 유지한다면 `ViewpointRouter`의 `profileGeometry` 라우팅은 방향 위반이다.
   - 선택 B: "자동 시점 인식은 실용상 2D profileGeometry를 포함한다"로 방향을 바꾸면 handoff/todo 문서를 업데이트해야 한다.

2. **fresh live run (2026-06-27 수행 완료 — 차단 발견)**
   - `make package` + 디버그/10초 주기로 정면 실행함. 결과: `coreMLRelativeDepth`는 `observedSignalKinds`에 `relativeDepth`가 **한 번도 안 잡힘**(`validFrameCount=0`, verdict noEval). 원인은 2D 신체 포즈 빈 결과(위 §Local Runtime Verification).
   - 따라서 배포 전 **최우선 차단 요인**은: 정면 웹캠 상체 프레임에서 `VNDetectHumanBodyPoseRequest`(2D)가 결과를 내도록 만들거나(예: 요청 revision/옵션·입력 전처리 재검토, 또는 3D 포즈를 1차 입력으로 승격), 제품 기본 경로를 3D 기반으로 전환해야 함. 현 상태로는 정면에서 어떤 verdict도 산출 불가.
   - 후속 확인: 3D 폴백(mlAuto)에서 재보정→`validFrameCount>0`의 good/bad verdict가 실제로 나오는지 라이브로 마무리(이번 세션 미실행, depth3D conf 0.70 6/8 관측으로 성공 전망).

3. **라우팅 + 보정 UX 확인**
   - 오른쪽 배치에서 `profileRight`/`threeQuarterRight`로 라우팅될 때 profile baseline이 없으면 재보정 안내가 자연스럽게 나오는지 확인.
   - 시점 변경 직후 재보정 실패 가능성이 있는지 live로 확인.

4. **문서 정리**
   - `docs/todo/handoff.md`의 ML-only/migration 설명을 현재 코드에 맞게 갱신하거나, 코드를 문서 방향으로 되돌린 뒤 갱신.
   - 테스트 수 `97/101/109` 표기를 현재 `110` 기준으로 갱신.
   - Depth Pro 라이선스 설명을 "HF `apple/DepthPro` weights는 research-only, GitHub/HF 표기 차이 존재"로 정밀화.

## Verdict

**빌드/테스트/패키징은 통과하지만, 정면 라이브에서 기본 경로가 동작하지 않아 배포 불가(FAIL).**

- 이전 리뷰는 차단 요인을 "제품 방향(ML-only vs 시점 라우터) 불일치"로 봤다. 2026-06-27 정면 실측은 더 근본적인 **기능적 차단**을 드러냈다: 제품 기본 경로(`coreMLRelativeDepth` 및 모든 2D 기하)가 의존하는 2D 신체 포즈가 이 OS(macOS 26.5.1)·정면 상체 웹캠 프레이밍에서 빈 결과를 반환해, 정면에서 어떤 자세 verdict도 산출되지 않는다.
- 모델·코드·패키징 자체는 정상이고, Core ML 추론 성능(~35ms)도 레퍼런스에 부합한다. 동작 가능한 라이브 경로는 3D 기반(mlAuto의 3D 폴백, depth3D conf 0.70)뿐이며, 이는 기존 문서가 "3D는 보조"라 전제한 것과 반대다.
- 배포 가능 판정 전 필요한 것: (1) 정면 입력원을 3D 포즈 기반으로 승격하거나 2D 신체 포즈가 이 프레이밍에서 결과를 내도록 해결, (2) ~16초 모델 콜드 로드/첫 버스트 무효 처리, (3) 3D 폴백 보정→good/bad verdict 라이브 완결 확인. 그 다음에야 "정면 동작"을 주장할 수 있다.
