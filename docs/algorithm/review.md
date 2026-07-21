# 리뷰: 알고리즘 규범 문서 (docs/algorithm/README.md, posture-analysis-workflow.md)

- 리뷰 일자: 2026-07-21
- 대상 문서:
  - [README.md](README.md)
  - [posture-analysis-workflow.md](posture-analysis-workflow.md)
- 종합 판정: 경미한 수정 권장

## 요약

알고리즘 규범 문서 그룹은 전반적으로 품질이 높다. README의 문서 구성 트리는 실제 디렉토리와 정확히 일치하고 그룹 내 내부 링크가 모두 유효하며, feature 수식·hysteresis 이중 경계·버스트 중앙값/MAD 집계·상태 전이 횟수·debug 산출물 경로·local AI CLI 계약 등 대부분의 규범 서술이 구현과 외부 근거(Depth Anything V2 relative inverse depth, Apple PoseNet 샘플)에 부합한다. 다인 장면 모호성에 대한 major 지적 1건은 검증 결과 기각됐고, 불충분 증거의 장기 지속 처리·버스트 프레임 수 하한·README 상단 면책 문구 등 경미한 불일치만 남았다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| Depth Anything V2는 relative (inverse) depth를 출력하며 값이 클수록 가까움 (§5) | 외부 근거와 일치 | [HF CV course: monocular depth](https://huggingface.co/learn/computer-vision-course/en/unit8/monocular_depth_estimation), [DA-V2 issue #93](https://github.com/DepthAnything/Depth-Anything-V2/issues/93) |
| relative depth는 고정 scale·offset이 없어 프레임 간 직접 비교 불가 (§5) | scale/shift 모호성 근거와 일치 | [HF CV course: monocular depth](https://huggingface.co/learn/computer-vision-course/en/unit8/monocular_depth_estimation) |
| Apple Core ML 샘플 PoseNet은 실재하며 같은 모델이 저장소에 번들됨 | 확인 | [Apple 문서](https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image), `Resources/PoseNetMobileNet075S16FP16.mlmodel`, `Sources/TurtleCore/Camera/PoseNetDetector.swift:9` |
| Depth Anything V2 Small Core ML 패키지(Apache-2.0)는 Apple 배포 모델이며 동일 이름으로 번들됨 | 확인 | [apple/coreml-depth-anything-v2-small](https://huggingface.co/apple/coreml-depth-anything-v2-small), `Resources/DepthAnythingV2SmallF16.mlpackage`, `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift:16` |
| PoseNet 우선·Vision 2D fallback, 동일한 `PoseLandmarks` 계약 (§4) | 구현과 일치 | `Sources/TurtleCore/Camera/PoseDetector.swift:17-21` |
| feature = direction × (head - torso) / scale, 기준 ROI의 견고한 범위로 정규화 (§6) | 구현과 일치 | `Sources/TurtleCore/Detection/PostureAnalyzer.swift:119` |
| 버스트 대표값은 품질 통과 feature의 중앙값 + MAD 변동 범위, 유효 프레임 수·비율 확인 (§7) | 구현과 일치 | `Sources/TurtleCore/Detection/BurstProcessor.swift:24-54`, `Tuning.swift:19-21` |
| 악화 진입·정상 복귀 경계를 분리한 hysteresis, 사이는 불충분 증거 (§9) | 구현과 일치 | `Sources/TurtleCore/Detection/Tuning.swift:29-35` (worsening 0.35 / recovery 0.25), `BurstProcessor.swift:66-75` |
| bad 전이·정상 복귀·noEval 전환은 연속 확인 후에만 수행 (§10) | 연속 2·2·3회 잠정값으로 구현 | `Sources/TurtleCore/Detection/Tuning.swift:24-26`, `PostureStateMachine.swift:39-91` |
| 처리 완료 시각이 아닌 캡처 시작 시각 기준으로 다음 주기를 계산 (§10) | 구현과 일치 | `Sources/TurtleCore/Camera/CameraManager.swift:607-613, 852-858` |
| 분석 세션은 최소 20초 간격 | 설정 하한과 일치 | `Sources/TurtleCore/Storage/Settings.swift:73-75` (clampInterval: min 20, max 180) |
| debug 산출물 경로·파일명 규칙(타임스탬프 디렉토리, capture/overlay/depth/frame/session, -local의 request/analysis, 자릿수 채우기 없음) | 구현과 일치 | `Sources/TurtleCore/Output/DebugCaptureStore.swift:29,55-66,85`, `LocalAIAnalysisRunner.swift:39-47` |
| local AI CLI 요청에 depth가 절대 거리·cm가 아니라는 조건과 입력 디렉토리 수정 금지 포함 | 구현과 일치 | `Sources/TurtleCore/Output/LocalAIAnalysisRunner.swift:85-98` |
| baseline은 촬영 조건 변경 시 재보정 요구, 원본 이미지 미저장 (§8) | 구현과 일치 | `Sources/TurtleCore/Detection/Models.swift:335-337, 340-374`, `BurstProcessor.swift:62-64` |
| 회복 알림 없음, 상태 전이 + 최소 알림 간격 확인 (§11) | 구현과 일치 | `Sources/TurtleCore/Notifications/NotificationPolicy.swift:12-27` (최소 간격 25분) |
| README "현재 문서 구성" 트리 | 실제 `docs/algorithm/` 구성과 정확히 일치, 각 방식 디렉토리는 필수 3파일 보유 | `docs/algorithm/README.md:97-121` vs 디렉토리 실측 |
| 다인 장면에서 대상을 안정적으로 고를 수 없으면 noEval (§2) | 문서가 옳음. PoseNet decoder가 후보 1명만 반환해도 `maximumSubjectJump` 검사(단일 후보에도 적용)와 상체 유효성 게이트 후 Vision fallback(다중 observation)을 통해 규정된 noEval 결과에 도달 가능하다. 구현 간극이 있더라도 규범 문서 우선 원칙상 문서 수정 사유가 아니며, §14에 대상 선택 안정성이 검증 항목으로 존재한다 | `Sources/TurtleCore/Detection/SubjectSelector.swift:25,37-41`, `Camera/PoseDetector.swift:73-81`, `docs/algorithm/README.md:5` |

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

1. 불충분 증거의 장기 지속 처리 미정의
   - 파일: `docs/algorithm/posture-analysis-workflow.md`
   - 문서 서술: §9는 두 경계 사이를 "상태를 바꾸기에는 차이가 작음"으로만 정의하고, §10은 "평가 불가가 오래 이어질 때만 제품 상태를 noEval로 전환한다"고 서술한다.
   - 문제: 구현은 불충분 증거를 noEval 연속 집계에 포함해, 불충분 증거만 이어져도 제품 상태가 noEval로 전환된다. 문서는 불충분 증거의 장기 지속 시 처리(평가 불가 집계 포함 여부)를 정의하지 않아 §9·§10 서술과 어긋날 수 있다.
   - 근거: `Sources/TurtleCore/Detection/PostureStateMachine.swift:73-80` (.insufficient가 noEvalStreak 증가), `Tests/TurtleCoreTests/WorkflowTests.swift:225-226` (insufficient 연속으로 noEval 전환을 명시한 테스트)

2. 버스트 프레임 수 서술(3~5장)과 구현 하한(2장) 불일치
   - 파일: `docs/algorithm/posture-analysis-workflow.md`
   - 문서 서술: 서두 "한 세션에서는 3~5장의 짧은 이미지 버스트를 사용한다", §1 "제한된 시간 동안 3~5장의 프레임을 수집한다".
   - 문제: 구현은 총 프레임·유효 프레임 하한을 2장으로 두어(`minimumValidFrames = 2`) 2장짜리 버스트도 판정을 진행한다. Tuning이 스스로 잠정값이라 명시하고 문서도 시간 예산 종료를 허용하므로 불일치 사실만 기록한다.
   - 근거: `Sources/TurtleCore/Detection/Tuning.swift:20`, `BurstProcessor.swift:41-51`, `CameraManager.swift:836` (maximumAnalysisFrames = 5)

3. README 상단 면책 문구가 문서 역할과 충돌
   - 파일: `docs/algorithm/README.md`
   - 문서 서술: 1행 인용구 "이 문서는 참고용 리서치이며, 현재 확정된 제품 플로우를 직접 정의하거나 구현 기준으로 활용하지 않습니다."
   - 문제: 이 README는 참고용 리서치가 아니라 규범 문서 우선순위·파일 규칙·적용 상태 용어를 정의하는 문서 체계 규칙이며, 같은 문서에서 posture-analysis-workflow.md를 구현이 따르는 규범 문서(우선순위 1)로 지정한다. 상단 면책 문구가 디렉토리 전체를 참고용으로 읽게 만들 수 있다.
   - 근거: `docs/algorithm/README.md:3` vs `README.md:11,19`, `docs/algorithm/posture-analysis-workflow.md:3`

## 참고 (info)

- depth map과 landmark 좌표 불일치의 검출 수단 미확인
  - 파일: `docs/algorithm/posture-analysis-workflow.md` §12 실패 처리 표의 "depth map과 landmark 좌표 불일치 → 분석 중단, noEval" 항목.
  - 구현에는 두 경로의 좌표 불일치를 런타임에 검출하는 명시적 수단이 없다. 둘 다 같은 sample buffer와 orientation .up을 사용하며, ROI가 단위 사각형을 벗어나는 간접 케이스만 빈 값으로 처리된다. 이 실패 항목이 실제로 어떻게 감지·중단되는지는 코드로 확인할 수 없다. apple-body-pose/checklist.md도 scaleFill 좌표 일치를 별도 검증 항목으로 두고 있다.
  - 근거: `Sources/TurtleCore/Camera/CameraManager.swift:395-449`, `Models.swift:161-176`

## 결론

두 문서의 규범 서술은 구현·외부 근거와 대부분 일치하며, 기각되지 않은 major 지적은 없다. 남은 사항은 불충분 증거의 장기 지속 처리 정의, 버스트 프레임 수 하한 표기, README 면책 문구 정리의 세 가지 경미한 수정이다. 이 중 첫 번째(불충분 증거의 noEval 집계 포함 여부)는 상태 전이 의미에 닿아 있으므로 문서에서 명시적으로 정의하는 것을 권장한다.
