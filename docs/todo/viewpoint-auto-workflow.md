# 시점 인식 자동 워크플로우 설계

맥북 배치가 정면/측면/3-4로 바뀔 수 있으므로, **주기적으로 시점을 분석해 그 시점에 맞는 분석 방식을 자동 선택**하는 워크플로우. 사용자 요구: ① 실행 중 몇 틱마다 '시점 분석'(자세 재보정과 별개), ② 시점에 맞는 방식 자동 선택, ③ 수동 방식 선택은 디버그 모드 전용.

## 설계 근거 데이터 (로컬 실측)

- 측면(profile)에서 **보정 통과 + 실제 판정을 낸 유일한 신호 = `profileGeometry`(profile2D, conf 0.25~0.31 ≥ 보정임계 0.2)**. 3D 독립이라 안정적.
- Vision 3D(depthDelta·bodyFrame3D)는 측면서 발화하나 **conf 0.37~0.45로 보정임계 0.5를 구조적으로 못 넘음** → 영원히 "기준없음"(측면 보정 실패의 원인).
- Core ML `relativeDepth`는 보정임계 **0.2**라 정면 live에서 잡힘 → 정면 depth는 Vision 3D보다 Core ML이 현실적.
- 신뢰도 보정임계(`Calibrator`): profile2D/threeQuarter2D/relativeDepth/frontFace = **0.2**(`minimumTrackingConfidence`), front2D/body3D/depth3D = **0.5**(`minimumLandmarkConfidence`).

## 시점 → 방식 매핑

| 시점 band | 자동 선택 방식 | 근거 |
|---|---|---|
| `front` | `coreMLRelativeDepth` | 정면은 depth 필요(리서치). Core ML은 0.2 임계·전 기기·정면 live 발화 |
| `profileLeft`/`profileRight` | `profileGeometry` (profile2D) | 측면서 유일하게 보정 통과·판정 산출(실측) |
| `threeQuarterLeft`/`threeQuarterRight` | `profileGeometry` (threeQuarter2D) | 2D 시상 기하, 0.2 임계 |
| `unknown` | 직전 라우팅 방식 유지(없으면 noEval) | 플래핑 방지 |

- Vision 3D(`depthDelta`·`bodyFrame3D`)는 웹캠서 0.5 임계 미달로 보정 불가 구조 → **자동 라우팅 후보에서 제외, 디버그 수동 선택으로만 유지.**

## 워크플로우

1. **매 버스트 시점 산출.** 2D pose(귀/눈/yaw)는 depth/3D 없이 항상 가용 → `ViewpointClassifier`로 프레임별 분류, 버스트의 지배 band를 `finishBurst`(serial `queue`)에서 집계.
2. **히스테리시스 K=2 (= "몇 틱 후 시점 분석").** 새 band가 **2버스트 연속** 지배할 때만 라우팅 방식 전환. 플래핑 억제. 교차버스트 상태(`lastStableBand`, `routedAlgorithm`, 후보 카운터)를 `CameraManager`에 신설(serial queue).
3. **라우팅 ID를 `CaptureSnapshot`에 실음.** `processSampleBuffer`가 `requests3D`/`requestsCoreMLRelativeDepth`로 입력 제공을 결정하므로, 라우팅된 ID로 입력 제공과 알고리즘 선택을 일치시킴(불일치 시 3D로 라우팅했는데 데이터가 없어 noEval).
4. **baseline 없으면 noEval + "시점 변경 — 재보정 필요".** 라우팅 방식의 baseline 필드가 비면 자동 캡처하지 않고 안내만(`mlBaselineWarning` 재사용). 바른자세 확정은 '자세 재보정'으로만 — 요구사항의 "별개" 충족.
5. **방식 전환 시 `noEvalStreak` 리셋.** 시점 변경의 일시 noEval로 `PostureStateMachine`이 `needsCalibration`(noEval 3연속)→카메라 정지로 가는 오발 방지.
6. **수동 방식 선택 = 디버그 전용.** `Settings.debugEnabled`(이미 존재) off → 라우터만 사용, on → 기존 방식 picker로 수동 override. `effectiveAlgorithm = debugEnabled ? settings.postureAlgorithm : router(band)`. 신규 enum 케이스 불필요.

## 컴포넌트 / 통합 지점 (코드 조사 기반)

- 신규 `ViewpointRouter`(순수 함수, 테스트 가능): `(band, baseline) → PostureAlgorithmID`(+ baseline 유무 반영).
- `CameraManager`: `routedAlgorithm`·`lastStableBand`·`pendingBand`·`pendingCount` 상태; `finishBurst`(`:236` 이후, check 경로)에서 지배 band 집계 + 히스테리시스 갱신; serial `queue`에서만 접근.
- `CaptureSnapshot`(`:565`)에 `effectiveAlgorithm` 추가 → `processSampleBuffer`(`:471`/`:475`)와 `PosturePipeline.process`의 `Factory.make`(`:37`)가 이를 사용.
- `MenuView`: 방식 picker(`:63-74`)를 `if model.settings.debugEnabled` 안으로 이동(디버그 picker엔 `profileGeometry`/`frontProxy`도 노출해 측면 테스트 가능).
- `BurstProcessor`/`PostureStateMachine`: 전환 시 streak 리셋 훅.

## 엣지/주의

- `.unknown` 폴백: 직전 라우팅 방식 유지(교차버스트 메모리). 최초/메모리 없음 → 정면 가정(coreMLRelativeDepth) 또는 noEval.
- 보정/즉시점검 버스트는 카운터에서 제외(시점 틱은 일반 check 버스트만).
- 라우팅은 **버스트 간**에만(버스트 내 방식 변경은 1€ 필터 churn → 금지).
- 시점 분류 신뢰도는 휴리스틱(정면 0.9, 측면 0.72~0.82, 3-4 0.58~0.66) — 안정 band 판단에 confidence 가중.

## 테스트 계획

- `ViewpointRouter`: band별 매핑 단위테스트(front→coreML, profile→profileGeometry, 3-4→profileGeometry, unknown→직전유지).
- 히스테리시스: K=2 연속에서만 전환, 1회 깜빡임은 미전환.
- baseline 누락: 라우팅 방식 baseline 없으면 noEval + 경고 메시지.
- 전환 시 noEvalStreak 리셋.
- debug on/off에 따른 effectiveAlgorithm(수동 vs 라우터).
- 회귀: 기존 `scripts/run-tests.sh` 전체 통과 유지.
