# Review

Last updated: 2026-06-26 11:45 KST

## Scope

검토 대상:

- `docs/todo/handoff.md`
- `docs/algorithm/**`
- `docs/depth-estimation/**`
- `docs/todo/local-llm-ai-cli-plan.md`
- `docs/todo/viewpoint-auto-workflow.md`
- 현재 코드/테스트/패키징 상태

이번 작업은 리뷰가 목적이므로 코드는 수정하지 않았다. 명확한 불일치와 배포 전 리스크를 아래에 기록한다.

## Executive Summary

현재 상태는 **빌드/패키징은 가능하지만, 배포 가능 판정은 보류**가 맞다.

근거:

- `make check` 통과: `109 tests, 109 passed, 0 failed`.
- `make package` 통과: 앱 번들, ZIP, DMG 생성. `codesign --verify` 통과, universal binary `x86_64 arm64` 확인.
- 앱 번들에 `DepthAnythingV2SmallF16.mlpackage`와 `ThirdPartyNotices.md`가 포함됨.
- 리서치의 큰 결론은 웹/공식 자료와 대체로 맞다.
- 그러나 현재 제품 동작은 인수인계 문서의 "user-facing ML-only" 설명과 다르다. 디버그 off 상태에서 시점 라우터가 측면/3-4를 `profileGeometry`로 라우팅한다.
- 최신 `debug/latest/analysis.json`은 `algorithm=depthDelta`, baseline은 `relativeDepthDelta`만 있는 상태라 `noEval`이다. 이 실행은 정상 동작 확인 근거가 아니라, baseline/수동 방식 불일치 사례다.

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
- `scripts/run-tests.sh` 결과는 문서의 `97 tests passed`가 아니라 현재 `109 tests passed`다.
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

5. **최신 debug run은 정상 동작 근거가 아니다.**

   - `debug/latest/analysis.json`: `algorithm = depthDelta`, `baseline.relativeDepthDelta`만 존재, `observedSignalKinds = ["depth3D"]`, `validFrameCount = 0`, verdict `noEval`.
   - 이는 depthDelta baseline이 없는 상태에서 depthDelta를 수동 선택한 결과로 보인다.
   - Core ML 정상 판정 확인을 위해서는 `AI/ML 자동` 또는 `Core ML Depth Anything`으로 fresh run + 재보정 + 점검을 다시 해야 한다.

## Verification Run

실행한 검증:

```bash
make check
```

결과:

- `109 tests, 109 passed, 0 failed`
- Swift package build passed
- SwiftPM user cache/write warning과 missing `CLAUDE.md` exclude warning은 있었지만 실패는 아님.

```bash
make package
```

결과:

- `.build/turtlemeck.app` 생성
- `.build/turtlemeck.zip` 생성
- `.build/turtlemeck.dmg` 생성
- `codesign --verify --deep --strict --verbose=2 .build/turtlemeck.app` 통과
- universal binary: `x86_64 arm64`
- `hdiutil create -format UDZO`는 `장치가 구성되지 않았음`으로 실패했지만, 스크립트의 `hdiutil makehybrid` fallback이 성공해 DMG는 생성됨.

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

## Deployment Gate

현재 상태에서 배포 전 필요한 확인:

1. **제품 방향 확정**
   - 선택 A: "ML-only"를 유지한다면 `ViewpointRouter`의 `profileGeometry` 라우팅은 방향 위반이다.
   - 선택 B: "자동 시점 인식은 실용상 2D profileGeometry를 포함한다"로 방향을 바꾸면 handoff/todo 문서를 업데이트해야 한다.

2. **fresh live run**
   - `make fresh-run`
   - debug mode on
   - `AI/ML 자동` 또는 `Core ML Depth Anything` 선택
   - 재보정
   - `지금 점검`
   - `debug/latest/analysis.json`에서 `observedSignalKinds`에 `relativeDepth`가 있고 `validFrameCount > 0`인지 확인
   - 현재 남아 있는 `depthDelta` debug run으로는 정상 판정 불가.

3. **라우팅 + 보정 UX 확인**
   - 오른쪽 배치에서 `profileRight`/`threeQuarterRight`로 라우팅될 때 profile baseline이 없으면 재보정 안내가 자연스럽게 나오는지 확인.
   - 시점 변경 직후 재보정 실패 가능성이 있는지 live로 확인.

4. **문서 정리**
   - `docs/todo/handoff.md`의 ML-only/migration 설명을 현재 코드에 맞게 갱신하거나, 코드를 문서 방향으로 되돌린 뒤 갱신.
   - 테스트 수 `97/101` 표기를 현재 `109` 기준으로 갱신.
   - Depth Pro 라이선스 설명을 "HF `apple/DepthPro` weights는 research-only, GitHub/HF 표기 차이 존재"로 정밀화.

## Verdict

**빌드 산출물 생성과 기본 테스트 기준은 통과. 하지만 배포 가능 상태로 확정하기에는 아직 이르다.**

가장 큰 이유는 코드 품질 문제가 아니라 제품 방향 불일치다. 현재 구현은 "ML-only"가 아니라 "정면은 Core ML depth, 측면/3-4는 profileGeometry"인 자동 시점 라우터다. 이 방향을 제품 의사결정으로 확정하면 코드 구조는 대체로 타당하다. 반대로 ML-only가 최종 요구라면 현재 라우터 구현은 수정 대상이다.
