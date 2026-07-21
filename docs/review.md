# 리뷰: 제품 워크플로우 개론 (docs/workflow.md)

- 리뷰 일자: 2026-07-21
- 대상 문서: docs/workflow.md
- 종합 판정: 경미한 수정 권장

## 요약

docs/workflow.md는 개론 문서임에도 debug 산출물 경로·파일명·local AI CLI 계약 같은 구체 서술이 대부분 코드(DebugCaptureStore, LocalAIAnalysisRunner, CameraManager, BurstProcessor)와 정확히 일치하고, 규범 문서 posture-analysis-workflow.md와도 충돌이 없다. 외부 기술 주장(PoseNet 17관절, Vision 2D 19 point, Depth Anything V2의 relative inverse depth)도 근거가 확인됐고 상세 문서 링크 11개도 모두 유효하다. 다만 local AI CLI에 "analysis.md를 생성하도록 요청한다"는 서술은 실제 요청 계약(CLI는 텍스트만 반환하고 runner가 stdout·stderr를 analysis.md에 기록)과 달라 수정을 권장한다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| debug 산출물은 프로젝트 루트 `debug/{timestamp}`에 `capture-{n}.png`·`overlay-{n}.png`·`depth-{n}.png`·`frame-{n}.json`·`session.json`으로 생성되며 timestamp는 `yyyyMMdd-HHmmss` 형식 | 일치 | Sources/TurtleCore/Output/DebugCaptureStore.swift:24-37(포맷·디렉토리 생성), 45-86(파일명), 163-182(프로젝트 루트 탐색) |
| 프레임 번호는 캡처 순서대로 `1`부터 시작, 자릿수 채우기 없음, 같은 프레임의 capture/overlay/depth/frame 파일이 같은 번호 사용 | 일치 | Sources/TurtleCore/Camera/CameraManager.swift:375-393(enqueuedFrameCount+1을 frameIndex로 사용), DebugCaptureStore.swift:55-66(`"capture-\(index).png"` 등 동일 index) |
| `debug/{timestamp}-local`은 공통 세션과 같은 timestamp 사용, `request.md`·`analysis.md` 포함, local AI CLI 사용 시에만 생성 | 일치 | Sources/TurtleCore/Output/LocalAIAnalysisRunner.swift:33-48(공통 경로에 `-local` 접미사, request.md·analysis.md 생성, configuration 없으면 즉시 반환) |
| local AI CLI에 `debug/{timestamp}`의 기존 `capture-{n}.png`·`depth-{n}.png` 경로를 전달하고 재캡처·depth 재생성 없음, depth PNG가 상대 깊이 시각화라는 조건(비 cm·비 CVA·비진단)을 요청문에 포함 | 일치 | LocalAIAnalysisRunner.swift:69-98(디렉토리의 기존 파일 나열, "The depth PNG is a visualization of relative inverse depth. It is not centimeters, absolute distance, clinical CVA, or a medical diagnosis.") |
| CLI 응답은 공통 판정(good/bad/noEval·알림)에 재입력되지 않고 CLI 실행 실패도 판정을 바꾸지 않음 | 일치 | LocalAIAnalysisRunner.swift:23-24,33,64-66(반환값 없음, 오류 무시), CameraManager.swift:300-330,563-604(verdict·상태 확정 후 출력 단계에서만 runner 실행) |
| prod에서는 임시 파일을 생성하지 않고 debug 설정(또는 local AI 활성)일 때만 debug 세션 디렉토리 생성, 파일 출력은 판정 확정 후 결과를 읽기만 함 | 일치 | CameraManager.swift:188-190(`settings.debugEnabled \|\| localAnalysisRunner.isEnabled` 조건), 300-330(판정 계산 후 deliverDiagnostic 호출) |
| 분석 세션은 최소 20초 간격으로 실행(설정값 20~180초 clamp) | 일치 | Sources/TurtleCore/Storage/Settings.swift:73-75(`min(180, max(20, value))`) |
| 2D landmark는 PoseNet 우선, 유효한 상체가 없을 때 Apple Vision 2D(VNDetectHumanBodyPoseRequest)로 fallback | 일치 | Sources/TurtleCore/Camera/PoseDetector.swift:17-21,28-32(PoseNet 결과가 usable하면 반환, 아니면 Vision 수행) |
| 한 정기 점검의 악화는 후보로만 유지, 연속 두 번의 악화 증거에서만 bad 확정, 다음 점검 주기는 캡처 시작 시각 기준, 알림은 bad 전이 시에만 후보 | 일치 | Sources/TurtleCore/Detection/Tuning.swift:24(requiredBadBursts=2), Sources/TurtleCore/Detection/PostureStateMachine.swift:41-54(전이 시에만 .cautionStarted), CameraManager.swift:607-613,852-858(remainingCheckDelay가 startedAt 기준) |
| 알림 정책은 자세 재판정 없이 알림 시점과 반복 제한만 담당(최소 25분 간격·스누즈, 회복 알림 미발송) | 일치 | Sources/TurtleCore/Notifications/NotificationPolicy.swift:8-31(cautionStarted만 허용, minimumInterval 25*60) |
| Apple Core ML 샘플 PoseNet은 17개 관절을 검출 | 일치 | https://developer.apple.com/documentation/coreml/model_integration_samples/detecting_human_body_poses_in_an_image ("PoseNet models detect 17 different body parts or joints") |
| Apple Vision 2D body pose는 19개 body point 제공 | 일치 | https://developer.apple.com/videos/play/wwdc2020/10653/ ("19 unique body points") |
| Depth Anything V2(relative 버전)는 affine-invariant relative inverse-depth를 출력하며 절대 거리를 제공하지 않음 | 일치 | https://arxiv.org/html/2406.09414v1 (affine-invariant inverse depth 예측) |
| 번들 모델 DepthAnythingV2SmallF16.mlpackage(Apache-2.0)와 PoseNetMobileNet075S16FP16.mlmodel이 실제 존재하고 코드가 해당 이름으로 로드 | 일치 | Resources/ 디렉토리 확인, Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift:16, https://huggingface.co/apple/coreml-depth-anything-v2-small (license apache-2.0) |
| 상세 문서 표의 링크 11개가 모두 실제 파일로 존재, "사용하지 않는 경로"(Vision 3D·하드웨어 depth·얼굴/사람 분할 모델)가 실제로 코드에 없음 | 일치 | docs/ 파일 존재 확인(11개 모두 확인), Sources/ 전체 grep에서 Pose3D·AVDepthData·FaceLandmarks·PersonSegmentation 미검출 |

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

- **local AI CLI 요청 계약 서술이 실제 동작과 다름** (docs/workflow.md:127, 139)
  - 문서 서술: "local AI CLI에는 depth 이미지가 상대 깊이라는 조건과 함께 `analysis.md`를 생성하도록 요청한다", "모든 결과를 `debug/{timestamp}-local`에 생성하도록 요청한다".
  - 문제: 실제 요청문은 CLI에 "Return only a concise wellness-oriented analysis; the caller writes it to: …analysis.md"라고 지시하고, `analysis.md`는 runner가 미리 빈 파일로 생성한 뒤 CLI의 stdout·stderr를 리다이렉트해 기록한다. 즉 CLI가 `-local`에 결과 파일을 생성하는 것이 아니라 텍스트만 반환하며, CLI 실패 시 stderr 오류 텍스트가 analysis.md에 섞일 수 있다. 규범 문서(docs/algorithm/posture-analysis-workflow.md:59-64)도 같은 방식으로 서술하고 있어 두 문서의 요청 계약 서술을 실제 동작에 맞게 고치는 것이 좋다.
  - 근거: Sources/TurtleCore/Output/LocalAIAnalysisRunner.swift:45-59(빈 analysis.md 생성 후 stdout/stderr 리다이렉트), 85-98(요청문 원문)

## 참고 (info)

- **"3~5장 캡처"의 하한은 코드가 강제하지 않음** (docs/workflow.md:9, 123)
  - 상한 5장은 CameraBurstTiming.maximumAnalysisFrames=5로 강제되지만, 하한 3장은 강제되지 않는다. BurstProcessor는 유효 프레임 2장(Tuning.minimumValidFrames=2)이면 판정을 진행하므로, 카메라가 프레임을 늦게 전달하는 경계 사례에서는 2장짜리 버스트도 정상 판정될 수 있다. 다만 Tuning은 잠정값임을 명시하고 있고 통상 동작(0.4초 간격 × 2.4초 수집)에서는 5장이 목표라 실사용 영향은 작다.
  - 근거: Sources/TurtleCore/Camera/CameraManager.swift:832-849, Sources/TurtleCore/Detection/BurstProcessor.swift:41-51, Sources/TurtleCore/Detection/Tuning.swift:20-21
- **debug 스펙이 개론과 규범 문서에 중복 정의됨** (docs/workflow.md:103-144)
  - docs/algorithm/README.md:19는 "상위 workflow.md는 개론이므로 상세 판단을 새로 정의하거나 하위 문서의 결정을 바꾸지 않는다"고 규정하는데, 규범 문서 posture-analysis-workflow.md:9는 prod/debug 출력 구분과 local AI CLI 경로를 오히려 개론에 위임하면서 자체 "디버그 산출물 경로" 절(35-68행)에서 같은 스펙을 중복 정의한다. 현재 두 문서의 내용은 일치해 실질 충돌은 없지만, 우선순위 규칙과 위임 방향이 어긋나 있어 향후 한쪽만 수정될 때 불일치가 생기기 쉽다.
  - 근거: docs/algorithm/README.md:19, docs/algorithm/posture-analysis-workflow.md:9,35-68, docs/workflow.md:103-144

## 결론

개론의 사실 서술은 코드·규범 문서·외부 근거와 폭넓게 일치하며, 기각되지 않은 major 지적은 없다. local AI CLI 요청 계약 서술 1건만 실제 동작에 맞게 수정하면 되고, "3~5장" 하한과 debug 스펙 중복 정의는 참고 수준이다. 종합 판정은 "경미한 수정 권장"이다.
