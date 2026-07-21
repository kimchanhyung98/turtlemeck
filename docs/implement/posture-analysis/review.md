# 리뷰: 자세 분석 구현 결정 (docs/implement/posture-analysis/)

- 리뷰 일자: 2026-07-21
- 대상 문서: docs/implement/posture-analysis/README.md
- 종합 판정: 경미한 수정 권장

## 요약

이 문서는 전체가 코드 정합성 주장인데, 도메인 경계 표의 타입·디렉토리 배치, 캡처·상태·출력 결정, Tuning 수치, 환경변수, baseline 저장 항목, 검증 명령과 테스트 커버리지까지 대조한 항목 전부가 현재 소스와 정확히 일치했다. "2026-07-21 장치 검증 반영" 절의 수치는 리포지토리의 debug 세션 산출물로 실측 근거까지 확인됐고, 외부 주장(Apple 공식 샘플 PoseNet, Apple의 DA-V2 Small Core ML 릴리스)도 1차 출처로 검증됐다. 남은 지적은 local AI `analysis.md` 생성 주체에 대한 규범 문서와의 서술 차이 1건(코드와는 이 문서가 일치)과 참고 수준 2건뿐이다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| 도메인 경계 표의 핵심 타입이 실재하고 Camera/·Detection/·Output/ 디렉토리 배치가 일치 | 일치 | Sources/TurtleCore/Camera/{CameraManager,PoseDetector,PoseNetDetector,CoreMLRelativeDepthProvider}.swift, Detection/{SubjectSelector.swift:9, PostureAnalyzer.swift:4, BurstProcessor.swift:15, Calibrator.swift:13, PostureStateMachine.swift:13}, Output/{DebugCaptureStore.swift:16, LocalAIAnalysisRunner.swift:24} |
| 픽셀 포맷을 420f→420v→BGRA 순으로 명시 고정, 노출 게이트는 미지원 포맷에서 fail-closed | 일치 | Sources/TurtleCore/Camera/CameraManager.swift:476-484(preferredPixelFormats), 741-749(default: return false) |
| `cautionStarted`는 `bad` 전이 확정 시에만 발생, `recovered`는 일일 통계에만 반영되고 알림 미발송, NotificationPolicy가 최소 간격·스누즈로 별도 제한 | 일치 | Sources/TurtleCore/Detection/PostureStateMachine.swift:49-53,64-71; Notifications/NotificationPolicy.swift:8-27(guard alert == .cautionStarted); App/AppModel.swift:265-277; Tests/TurtleCoreTests/ProductTests.swift:66-71 |
| shoulder confidence 0.15·머리 anchor 0.5·접촉률 상한 0.55·버스트 수 2/2/3·유효 프레임 최소 2·`largerIsNear`가 모두 Tuning에 존재 | 일치 | Sources/TurtleCore/Detection/Tuning.swift:5-6, 11, 20, 24-27 |
| local AI는 `TURTLEMECK_LOCAL_AI_EXECUTABLE`이 절대 경로일 때만 실행, 인자는 `TURTLEMECK_LOCAL_AI_ARGUMENTS_JSON`의 JSON 문자열 배열, 요청문 stdin·stdout/stderr는 `debug/{timestamp}-local/analysis.md`에 기록 | 일치 | Sources/TurtleCore/Output/LocalAIAnalysisRunner.swift:8-20(hasPrefix("/"), JSONDecoder [String]), 50-63(stdin pipe, analysis.md FileHandle) |
| 번호가 같은 `capture-{n}`·`depth-{n}` 쌍만 전달되어 depth 없는 프레임이 나머지 쌍을 막지 않음 | 일치 | Sources/TurtleCore/Output/LocalAIAnalysisRunner.swift:70-84(교집합), Tests/TurtleCoreTests/ProductTests.swift:92-111 |
| 기본 debug root는 source·bundle·실행 경로·cwd에서 Package.swift 탐색, `TURTLEMECK_DEBUG_ROOT` 절대 경로 지정 가능 | 일치 | Sources/TurtleCore/Output/DebugCaptureStore.swift:163-202 |
| baseline은 카메라 식별자·640×480·`up-unmirrored` 구성을 함께 저장, 구성이 다르면 `noEval`·재보정 필요 | 일치 | Sources/TurtleCore/Camera/CameraManager.swift:486-491; Detection/BurstProcessor.swift:59-64 + Models.swift:335-338(requiresCalibration) |
| debug 세션은 `debug/yyyyMMdd-HHmmss`에 capture/overlay/depth/frame-{n}·session.json 기록, 번호는 1부터 무패딩, 보정 중간 버스트는 `calibrating` | 일치 | Sources/TurtleCore/Output/DebugCaptureStore.swift:24-37,55-66,85; Camera/CameraManager.swift:252-272; Tests/TurtleCoreTests/WorkflowTests.swift:257-268; 실측 debug/20260720-135202~135227 session.json |
| 보정 중 즉시 점검 무시, 다음 정기 점검은 이전 캡처 시작 시각 기준, 점검 간격 최소 20초 강제 | 일치 | Sources/TurtleCore/Camera/CameraManager.swift:112-116, 607-613, 852-858; Storage/Settings.swift:73-75(min(180, max(20, value))); Tests/TurtleCoreTests/ProductTests.swift:6-13,31-51 |
| PoseNet 후보가 confidence·기하 조건을 통과하지 못할 때만 Vision 2D fallback, Vision 요청은 지원 단계에서 CPU 장치 명시, pose 오류는 `modelFailure`로 기록 | 일치 | Sources/TurtleCore/Camera/PoseDetector.swift:17-21, 36-45, 73-81; Camera/CameraManager.swift:407-414 |
| PoseNetMobileNet075S16FP16.mlmodel은 Apple 공식 Core ML 샘플(PoseFinder)의 모델, output stride 16이 코드와 일치 | 일치 | https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image; Sources/TurtleCore/Camera/PoseNetDetector.swift:9-11; Resources/PoseNetMobileNet075S16FP16.mlmodel |
| 번들 DepthAnythingV2SmallF16.mlpackage는 Apple이 공개한 공식 Core ML 변환본과 이름·형식 일치 | 일치 | https://huggingface.co/apple/coreml-depth-anything-v2-small; Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift:16; Resources/DepthAnythingV2SmallF16.mlpackage |
| 검증 명령(Tests/run.sh, swift build --disable-sandbox)이 실재하고, 나열된 테스트 커버리지 항목이 모두 실제 테스트로 존재 | 일치 | Tests/run.sh, Makefile:13-15; Tests/TurtleCoreTests/WorkflowTests.swift:6-269, ProductTests.swift:6-111 |
| 장치 검증 수치: baseline 중심 -1.752·분산 0.069·3버스트, 13:07:11 두 번째 정기 점검의 `noEval`(접촉률 0.519·0.529 프레임 2개 제외 — 0.55 완화 근거), 이후 5/5 유효 프레임 `good` 확정 | 일치 | debug/20260721-112402/session.json(center=-1.752, dispersion=0.069, burstCount=3), debug/20260721-130711/session.json(0/5 valid, roiBoundaryContactRatio 0.519/0.529), debug/20260721-112516/session.json(state=good, 5/5 valid) |

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

- 파일: docs/implement/posture-analysis/README.md
  - 문서 서술: "local 프로세스는 요청문을 stdin으로 받고 stdout/stderr를 같은 timestamp의 `debug/{timestamp}-local/analysis.md`에 기록한다", "이 문서는 두 규범을 변경하지 않는다".
  - 문제: 이 서술 자체는 코드(LocalAIAnalysisRunner.swift:50-63)와 정확히 일치하지만 규범 문서와 충돌한다. posture-analysis-workflow.md는 "`analysis.md` — local AI CLI가 생성한 자세 분석 결과", workflow.md는 "CLI에 `analysis.md`를 생성하도록 요청한다"고 서술해 생성 주체(CLI가 파일 생성 vs 앱이 stdout을 파일로 기록)가 서로 다르다. "두 규범을 변경하지 않는다"는 범위 선언과 달리 이 출력 계약은 규범의 문자적 서술과 다르게 구현·기록되어 있다. docs/review.md(2026-07-21)가 이미 workflow.md 측 수정을 권고했으므로 규범 동기화 전까지 두 문서가 상충 상태다.
  - 근거: docs/algorithm/posture-analysis-workflow.md:60, docs/workflow.md:127 vs Sources/TurtleCore/Output/LocalAIAnalysisRunner.swift:50-63; docs/review.md 요약·상세(동일 지적으로 workflow.md 수정 권장)

## 참고 (info)

- 문서와 규범이 전제하는 hysteresis(악화 진입 경계와 회복 경계 분리)가 Tuning 구현에서는 baseline dispersion이 약 0.117(0.35/3)을 넘으면 worseningMargin과 recoveryMargin이 모두 dispersion×3으로 일치해 "두 경계 사이 불충분 증거" 구간이 소멸한다. 문서가 이 값들을 잠정값·검증 필요로 명시하므로 오류는 아니지만, 구현 결정 기록으로서 이 경계 붕괴 조건은 언급되지 않았다. 근거: Sources/TurtleCore/Detection/Tuning.swift:29-35(worseningMargin=max(0.35, d*3), recoveryMargin=max(0.25, d*3)); docs/algorithm/posture-analysis-workflow.md의 경계 분리 요구.
- 이 문서는 리포지토리의 어떤 인덱스 문서에서도 링크되지 않는다. docs/workflow.md의 상세 문서 표와 docs/algorithm/README.md의 문서 구성 트리 모두 docs/implement/를 포함하지 않고, docs/implement/에는 상위 README도 없다. kebab-case·README 진입점 규칙은 준수하므로 형식 위반은 아니나, 규범→구현 결정으로 이어지는 문서 체계에서 발견성이 떨어진다.

## 결론

대조한 코드 정합성 주장 전부가 현재 소스·debug 산출물·외부 1차 출처와 일치해 문서 품질이 매우 높다. major 오류는 없다. local AI `analysis.md` 생성 주체 서술은 코드 기준으로 이 문서가 옳으므로, 이미 권고된 workflow.md·posture-analysis-workflow.md 측 수정으로 규범을 동기화하면 상충이 해소된다. 인덱스 문서에 docs/implement/ 링크를 추가하면 발견성이 개선된다.
