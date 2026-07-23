# 자세 분석 구현 결정

## 범위

이 문서는 최신 규범인 [`../../workflow.md`](../../workflow.md)와 그 상세 판단 순서인 [`../../algorithm/posture-analysis-workflow.md`](../../algorithm/posture-analysis-workflow.md)를 코드에 반영하면서 정한 구현 경계와 아직 제품 데이터가 필요한 항목을 기록한다. 이 문서는 두 규범을 변경하지 않는다.

PoseNet의 모델·decoder 계약은 [`../../algorithm/apple-posenet/`](../../algorithm/apple-posenet/), 운영체제 Vision fallback 계약은 [`../../algorithm/apple-body-pose/analysis.md`](../../algorithm/apple-body-pose/analysis.md)에서 분리해 관리한다.

## 도메인 경계

| 영역 | 핵심 타입 | 책임 |
|---|---|---|
| 카메라 입력 | `CameraManager` | 최소 15초 간격, 안정화 후 최대 5장 수집, 버스트 스케줄·노출 게이트, 추론→판정→출력 단계 오케스트레이션 |
| 모델 추론 | `PoseDetector`, `PoseNetDetector`, `CoreMLRelativeDepthProvider` | PoseNet 우선·Vision fallback과 좌표 변환, DA-V2 relative depth |
| 대상 선택 | `UpperBodySubjectSelector` | 상체 크기와 버스트 내 위치 연속성으로 한 사람 유지, 모호하면 제외 |
| 프레임 분석 | `PostureFrameAnalyzer`, `UpperBodyGeometry` | 표준·머리 기준 측면 landmark 기하, 머리·몸통·reference ROI, median/IQR 정규화 feature |
| 버스트 판정 | `BurstProcessor` | 유효 비율, 중앙값·MAD, baseline과의 절대 거리 및 hysteresis 증거 |
| 보정 | `Calibrator` | 사용자가 명시적으로 저장한 기준 자세의 중심값·변동·캡처 구성 저장 |
| 시간 상태 | `PostureStateMachine` | 악화·회복 지속성, 장시간 `noEval`, `bad` 전이·회복 이벤트 |
| 출력 | `DebugCaptureStore`, `LocalAIAnalysisRunner` | 공통 결과를 읽어 debug/local 파일로 출력하며 판정에는 미입력 |

디렉토리도 도메인 경계를 따른다. 카메라 입력은 `Camera/`, 모델 어댑터는 `Inference/`, 판정 로직은 `Detection/`, 출력 계층은 `Output/`에 둔다.

기존의 시점별 2D 알고리즘, Vision 3D, 얼굴 proxy, 신호 융합, 알고리즘 선택 UI와 단일 강한 프레임 예외는 규범의 제외 범위에 따라 제거했다. 머리 기준 측면 ROI fallback은 별도 판정 알고리즘이나 별도 baseline을 만들지 않고 같은 relative-depth feature의 입력 기하만 안정화한다.

## 캡처 결정

- 카메라 출력 픽셀 포맷은 기본값이 기기 의존적이므로 `CameraFrameQuality`가 처리하는 포맷(420f → 420v → BGRA 순 선호)으로 명시적으로 고정한다. 노출 게이트는 미지원 포맷에서 fail-closed이므로, 고정하지 않으면 기기에 따라 모든 프레임이 제외될 수 있다.
- 워밍업 시간 이후에도 노출이 어두운 프레임은 `unstableCapture`로 제외하고, 판정을 채우기 위해 완화하지 않는다.

## 상태·이벤트 결정

- `bad` 전이 확정 시에만 `cautionStarted` 이벤트를 낸다. 알림 발송은 `NotificationPolicy`가 최소 간격·스누즈로 별도 제한한다.
- 회복 확정(`bad` → `good`) 시 `recovered` 이벤트를 낸다. 이 이벤트는 일일 통계에만 반영되고, 규범에 따라 알림으로는 보내지 않는다.
- `noEval`과 경계 사이의 불충분 증거는 모두 "판단을 확정할 수 없는 버스트"로 세어, 정해진 횟수 이상 이어지면 유지 중인 제품 상태를 `noEval`로 전환한다. 불충분 증거는 악화·회복 연속 횟수에는 포함하지 않는다.
- 보정이 진행 중일 때의 즉시 점검 요청은 무시한다. 받으면 즉시 점검 버스트가 보정 표본으로 흡수되기 때문이다.
- 저장된 baseline이 없으면 앱 시작 시 기존 보정 경로를 자동 실행한다. 별도 자동 재보정이나 일상 결과 기반 baseline 갱신은 하지 않는다.
- 악화는 정기 점검 두 번이 연속으로 악화일 때 확정한다. 첫 악화 뒤 별도 확인 타이머를 만들지 않고, 이전 캡처 시작 시각을 기준으로 설정된 정기 점검 주기를 그대로 사용한다.

## 출력 계약

- debug가 켜져도 prod와 같은 PoseNet·Vision 2D fallback, DA-V2 map, frame feature, burst 판정을 사용한다.
- 공통 프레임 분석과 제품 상태 전이를 먼저 끝낸 뒤 전용 출력 큐에서 이미지와 JSON을 기록한다. 출력 지연·실패는 버스트에 포함되는 프레임이나 제품 상태를 바꾸지 않는다.
- debug 세션은 `debug/yyyyMMdd-HHmmss`에 `capture-{n}.png`, `overlay-{n}.png`, `depth-{n}.png`, `frame-{n}.json`, `session.json`을 기록한다.
- 파일 번호는 `1`부터 시작하고 자릿수를 채우지 않는다.
- debug 화면은 이번 버스트 평가와 유지 중인 제품 상태를 구분하고, 프레임별 landmark·ROI·depth 요약·feature·품질·제외 사유와 단계별 처리 시간을 표시한다.
- `session.json`은 raw 버스트 평가, 지속성 적용 후 제품 상태, 프레임 진단, baseline delta와 단계별 처리 시간을 함께 기록한다.
- 여러 버스트를 사용하는 보정에서도 각 timestamp 디렉토리에 `session.json`을 기록한다. 중간 버스트의 제품 상태는 `calibrating`이다.
- local AI는 `TURTLEMECK_LOCAL_AI_EXECUTABLE`이 절대 경로로 설정된 경우에만 실행한다. 선택 인자는 `TURTLEMECK_LOCAL_AI_ARGUMENTS_JSON`의 JSON 문자열 배열로 전달한다.
- local 프로세스는 요청문을 stdin으로 받고 stdout/stderr를 같은 timestamp의 `debug/{timestamp}-local/analysis.md`에 기록한다. 실패와 응답은 공통 판정에 영향을 주지 않는다.
- local AI에는 실제로 생성된 `capture-{n}.png`와 `depth-{n}.png` 중 번호가 같은 쌍만 전달한다. 품질 실패로 depth가 없는 프레임 하나가 나머지 유효 쌍의 분석을 막지 않는다.
- 기본 debug root는 source·build·실행 경로에서 `Package.swift`를 찾아 결정한다. 패키징 환경에서 프로젝트 루트를 찾을 수 없으면 `TURTLEMECK_DEBUG_ROOT`로 `debug/` 절대 경로를 지정한다.
- baseline은 카메라 식별자, 640×480 분석 해상도와 `up-unmirrored` orientation을 함께 저장한다. 현재 캡처 구성이 다르거나 중심값·분산·버스트 수·feature version이 유효하지 않으면 해당 버스트는 `noEval`이며 재보정이 필요하다.

## 잠정값과 검증 필요 항목

다음 값은 제품 데이터로 계속 검증해야 하므로 `Tuning`에만 모아 두었다.

- landmark confidence, ROI 최소 픽셀과 유효 비율
- 머리·몸통 ROI 겹침 상한
- 대상 선택의 이동 상한, 후보 간 최소 분리, 크기 모호성 비율
- reference IQR 최소값과 버스트 MAD 상한
- 고정 악화·회복 경계와 baseline 분산 기반 경계
- 악화·회복·장시간 평가 불가에 필요한 버스트 수

ROI 크기 비례 계수(어깨 너비 기준)는 기하 설계값으로 `PostureFrameAnalyzer`에 두며, 위와 같이 제품 데이터 검증 대상이다.

DA-V2 방향은 현재 `largerIsNear`로 명시되어 있다. 코드 테스트는 방향 설정이 feature 부호를 정확히 바꾸는지만 검증한다. 실제 Apple Core ML 모델의 전처리까지 포함한 near/far 방향은 가까운 물체와 먼 물체가 명확한 고정 fixture로 별도 확인해야 한다. 이 실측 전에는 임계값과 자세 판정 성능을 확정된 것으로 간주하지 않는다.

## 2026-07-21 장치 검증 반영

제품 카메라의 가까운 상반신·측면에 가까운 실제 입력으로 확인한 실패와 수정 근거다.

- Vision 단독 경로는 모델 준비 오류 또는 landmark 미검출로 보정 프레임이 반복해서 0/5가 되었다. 오류를 빈 후보로 삼지 않고 `modelFailure`로 기록하며, Vision 요청은 지원되는 모든 단계에서 CPU 장치를 명시한다.
- Apple 공식 Core ML 샘플의 PoseNet을 우선 검출기로 추가했다. PoseNet 후보가 머리·양쪽 어깨의 추적 confidence와 표준·측면 기하 조건을 모두 통과하지 못할 때만 Vision 2D로 fallback한다.
- 측면에서 먼 쪽 어깨 confidence가 낮아지는 실제 분포를 반영해 shoulder 최소 confidence를 `0.15`로 두되, 머리 anchor는 `0.5`를 유지한다.
- 가까운 카메라에서 몸통 ROI가 화면 아래에 닿는 장면은 실제 보이는 영역을 unit square로 잘라 사용한다. 실측된 흐트러진 자세의 접촉률 `0.52`를 포함하도록 `0.55`까지 허용한다.
- 한 점검의 최대 5프레임 중 안정적인 유효 프레임이 2개 이상이면 평가한다. 이는 13:07:11의 두 번째 정기 점검이 유효 프레임을 확보하고도 `noEval`로 끊긴 문제를 바로잡는다.
- 한쪽 귀가 잘못 검출되어 머리 ROI 전체를 끌어가는 경우를 막기 위해 유효 머리 anchor의 중앙값을 ROI 중심으로 사용한다.
- 보정은 3개 버스트를 통과했고 마지막 버스트는 5/5 유효 프레임이었다. 저장된 baseline은 중심 `-1.752`, 분산 `0.069`였으며, 자동 점검도 5/5 유효 프레임으로 `good`을 확정했다. 이 값은 한 사용자·촬영 조건의 통합 검증 증거이지 다른 사용자에게 적용할 절대 임계가 아니다.

## 2026-07-22 장치 검증 반영

저녁·심야 debug 세션 19개(정상 자세, 턱 괴기, 옆 기울기, 전방 거북목, 측면 거북목, 빈 의자 — 각 세션에 `readme.md`·`data.md` 정적 분석 기록, 자세 라벨은 사용자 확정)로 확인한 실패와 수정 근거다.

- 몸통 ROI를 어깨 중점 + `0.34`sw(높이 `0.60`sw)에서 어깨선 밴드 어깨 중점 + `0.05`sw(높이 `0.20`sw)로 옮겼다. 구 기하는 어깨가 화면 하단(y 0.86~0.93)에 오는 전형 구도에서 42/42 프레임이 하단을 벗어나 경계 접촉률 `0.55` 임계 근처에서 프레임이 준무작위로 탈락했다. 밴드 기하는 같은 데이터에서 45/45 프레임 화면 안이며, depth PNG의 affine 불변 재구성으로 나쁜 자세 분리(같은 구도 good 대비 턱괴기+숙임 `+1.68`, 측면 거북목 `+0.66~0.71`, 전방 거북목 `+0.45`)가 유지됨을 확인했다.
- feature 정의 변경에 따라 `Baseline.featureVersion`(현재 3)을 저장하고, 버전이 다른 저장 baseline은 로드 시 무효화해 재보정을 안내한다. v3는 측면·3/4 ROI의 머리 기준 기하를 포함한다.
- 판정을 세 가지로 구분한다: 정상(feature와 baseline 비교), 비정상(머리는 감지되나 자세 때문에 정상을 확인할 수 없음 — baseline 비교 불요), 판정 불가(사람 없음). 자세 기인 평가 불가 프레임이 버스트 과반이면 `noEval`이 아니라 악화 증거로 처리한다. depth 품질·기하 실패(조명·모델 기인)는 악화 증거로 승격하지 않고, 사용자 크기(눈 사이 거리 `0.03`)에 못 미치는 원거리 인물의 머리는 사람 없음으로 남긴다.
- 턱 괴기 실측에서 팔이 어깨를 가려 어깨 confidence가 `0.14~0.31`로 무너졌고 정상 자세 최소값은 `0.51`이었다. 분석기에서 어깨 confidence `0.35` 미만은 `missingShoulder`(평가 불가 자세)로 제외한다. 대상 선택·추적의 `0.15` 하한은 유지한다.
- 옆 기울기·숙임 실측에서 (어깨midY − 신뢰 머리 anchor 중앙값 y)/어깨폭이 정상 최소 `0.945` 대비 기울기 `0.70`, 턱 괴기+숙임 `0.81`로 낮았다. 임계는 정상 최소값 아래 여유 `0.045`를 둔 `0.90`이며, `0.90` 미만은 `headDropped`로 제외한다. 눈 중점 기반으로 측정한 초기 수치(정상 1.04~1.28)는 게이트가 계산하는 anchor 중앙값 기준과 달라 폐기했다 — 계측 도구(analyze-image)도 게이트와 같은 정의로 출력한다.
- 자세 기인 평가 불가 프레임이 과반인 보정 시도는 `postureUnassessable`로 거부하고, 구도 안내가 아니라 "바른 자세로 다시 보정" 안내를 낸다.
- 구도·각도·방향이 바뀌면 재보정이 필요하다는 규범(§8)을 실측 가능하게 만들었다: baseline에 보정 시점의 어깨 기준 구도(중점 y·폭 중앙값)를 저장하고, 점검 버스트가 midY `0.05` 또는 폭 상대 `10%`를 벗어나면 판정 대신 `framing changed`로 재보정을 안내한다. 허용치는 실측(같은 구도 버스트 간 midY ≤`0.016`/폭 ≤`5%`, 실제 구도 변경 midY `0.072`/폭 `11~17%`) 기반이며, 나쁜 자세로 인한 기하 변화(측면 거북목 폭 `-3%`, 턱 괴기 `-7%`)는 허용치 안에 있어 검출 경로를 방해하지 않는다.
- baseline 판정은 signed delta의 양의 방향만 보지 않고 `abs(feature - baseline.center)`를 사용한다. 사용자가 비정상 자세를 기준으로 저장했을 때 객관적으로 정상인 자세도 기준에서 멀면 비정상이 되는 기준 자세 우선 규칙을 보장한다. signed delta 자체는 진단 출력에 유지한다.
- PoseNet 손목 채널은 판정 근거로 쓰지 않는다. 실측에서 손 유무·사람 유무와 무관하게 배경 고정점(≈0.69, 0.55)을 confidence 최대 `0.43`으로 반복 검출했다(빈 의자 포함). 손목 좌표는 진단 기록으로만 노출한다.
- Vision fallback이 0건일 때 PoseNet 부분 검출을 보존해, '사람 없음(`noSubject`)'과 '머리는 있으나 어깨 미신뢰(`missingShoulder`)'를 구분한다.
- 실물 검증: 정상 캡처 9/9 유효(feature -0.26~-1.26, 임계 인접 프레임 포함), 턱 괴기·옆 기울기·전방 거북목은 자세 기인 제외(`missingShoulder`/`headDropped`) 과반으로 비정상, 측면 거북목은 5/5 유효 + 같은 구도 baseline 대비 feature Δ`+0.66~0.71`로 비정상, 빈 의자 `noSubject`. 전방 거북목(20260721-235959)은 두 경로가 수렴한다: 4/5 자세 기인 제외 + 유효 프레임 feature Δ`+0.45` > margin `0.35`. 턱 괴기 자세로는 유효 프레임이 없어 보정 자체가 거부된다(직전 판 1버스트 보정이 턱 괴기 baseline center `+0.113`을 수용했던 문제 해소).

## 2026-07-23 측면 ROI 검증 반영

정상에 가까운 같은 3/4 자세에서 먼쪽 어깨가 의자·헤드레스트로 튀며 `excessiveRotation`과 `headDropped`가 반복된 실제 캡처를 반영했다.

- `20260723-175043`, `175102`, `175121`의 기존 결과는 각각 유효 `0/5`, `2/5`, `1/5`였고 마지막 보정은 `postureUnassessable`로 거부됐다. 머리 anchor와 실제 가까운 어깨는 안정적이었지만 반대쪽 어깨 y만 약 `0.13~0.23` 위로 튀었다.
- 머리 anchor confidence `0.5` 이상인 귀가 한쪽만 보이면 머리 중심 x·양 어깨 수평 폭을 사용한다. 몸통 ROI는 어깨 높이 차가 `0.08` 이상이면 화면 아래쪽 실제 어깨를, 그보다 작으면 머리 중심 x에 가까운 어깨를 기준 y로 사용한다. 머리 처짐 안전 조건은 높이 차와 무관하게 머리 중심 x에 가까운 어깨로 계산한다. ROI 기준·머리 인접 어깨는 모두 confidence `0.35` 이상이어야 하며, 양 어깨가 수평인데 한쪽 confidence만 낮은 기존 턱 괴기 입력은 fallback하지 않는다.
- 수정 바이너리로 위 15장을 연속 재실행한 결과 `15/15`가 유효했고 feature MAD는 각각 약 `0.018`, `0.104`, `0.209`로 보정 상한 `0.35`를 충족했다. 이후 `175133`, `175151`, `175224`, `175246`, `175329`도 `25/25` 유효였고, 손이 얼굴을 가린 `175529`는 기존과 같이 `4/5` 유효·`missingShoulder` 1장을 유지했다. 별도로 실제 고개 숙임 `145616`, `145828`, `145901`은 `15/15` `headDropped`를 유지했다.
- 확장 회귀에서 심한 숙임 `135956`, `144304`도 유효 `0/10`을 유지했다. 턱·목 받침 `140944`는 3장이 feature까지 도달하지만 버스트 MAD 약 `0.358`이 상한 `0.35`를 넘어 보정에서 제외된다. 손-턱 접촉 자체나 머리 위쪽의 저신뢰 어깨 점이 의자 오검출인지 가림인지 landmark만으로 단정하지는 않으므로, 세운 턱 괴기는 별도 신호 검증 전까지 알려진 한계다.
- `postureUnassessable`은 어깨 가림·잘림·회전·머리 처짐을 합친 사유이므로 안내에서 턱 괴기를 단정하지 않고 "바른 자세로 보정"만 요청한다.

## 검증 명령

```sh
Tests/run.sh
swift build --disable-sandbox
```

테스트는 affine scale·shift 불변성, 품질 실패, 머리 기준 측면 ROI와 기존 턱 괴기·머리 처짐 방어, 화면 경계 ROI clipping, 머리 anchor 이상치, 2~5장 버스트 집계, 여러 보정 버스트, 상태 지속성, 최소 점검 주기, 보정 안내, debug 파일명과 `session.json`의 제품 상태·프레임 진단·처리 시간, local RGB-depth 쌍 선택을 직접 확인한다. 실제 카메라 통합 경로는 위 장치 검증으로 별도 확인했다.
