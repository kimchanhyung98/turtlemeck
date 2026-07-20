# 자세 분석 구현 결정

## 범위

이 문서는 최신 규범인 [`../../workflow.md`](../../workflow.md)와 그 상세 판단 순서인 [`../../algorithm/posture-analysis-workflow.md`](../../algorithm/posture-analysis-workflow.md)를 코드에 반영하면서 정한 구현 경계와 아직 제품 데이터가 필요한 항목을 기록한다. 이 문서는 두 규범을 변경하지 않는다.

## 도메인 경계

| 영역 | 핵심 타입 | 책임 |
|---|---|---|
| 카메라 입력 | `CameraManager`, `PoseDetector` | 최소 20초 간격, 안정화 후 3~5장 수집, Vision 좌표 변환 |
| 대상 선택 | `UpperBodySubjectSelector` | 상체 크기와 버스트 내 위치 연속성으로 한 사람 유지, 모호하면 제외 |
| 프레임 분석 | `PostureFrameAnalyzer` | landmark 품질, 머리·몸통·reference ROI, median/IQR 정규화 feature |
| 버스트 판정 | `BurstProcessor` | 유효 비율, 중앙값·MAD, baseline delta와 hysteresis 증거 |
| 보정 | `Calibrator` | 안내된 중립 자세의 여러 버스트로 중심값·변동·캡처 구성 저장 |
| 시간 상태 | `PostureStateMachine` | 악화·회복 지속성, 장시간 `noEval`, `bad` 전이·회복 이벤트 |
| 출력 | `DebugCaptureStore`, `LocalAIAnalysisRunner` | 공통 결과를 읽어 debug/local 파일로 출력하며 판정에는 미입력 |

디렉토리도 도메인 경계를 따른다. 카메라 입력과 모델 어댑터는 `Camera/`, 판정 로직은 `Detection/`, 출력 계층은 `Output/`에 둔다.

기존의 시점별 2D 알고리즘, Vision 3D, 얼굴 proxy, 신호 융합, 알고리즘 선택 UI와 단일 강한 프레임 예외는 규범의 제외 범위에 따라 제거했다.

## 상태·이벤트 결정

- `bad` 전이 확정 시에만 `cautionStarted` 이벤트를 낸다. 알림 발송은 `NotificationPolicy`가 최소 간격·스누즈로 별도 제한한다.
- 회복 확정(`bad` → `good`) 시 `recovered` 이벤트를 낸다. 이 이벤트는 일일 통계에만 반영되고, 규범에 따라 알림으로는 보내지 않는다.
- 보정이 진행 중일 때의 즉시 점검 요청은 무시한다. 받으면 즉시 점검 버스트가 보정 표본으로 흡수되기 때문이다.

## 출력 계약

- debug가 켜져도 prod와 같은 Vision 2D, DA-V2 map, frame feature, burst 판정을 사용한다.
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
- baseline은 카메라 식별자, 640×480 분석 해상도와 `up-unmirrored` orientation을 함께 저장한다. 현재 캡처 구성이 다르면 해당 버스트는 `noEval`이며 재보정이 필요하다.

## 잠정값과 검증 필요 항목

다음 값은 제품 데이터로 확정되지 않았으므로 `Tuning`에만 모아 두었다.

- landmark confidence, ROI 최소 픽셀과 유효 비율
- 머리·몸통 ROI 겹침 상한
- 대상 선택의 이동 상한, 후보 간 최소 분리, 크기 모호성 비율
- reference IQR 최소값과 버스트 MAD 상한
- sensitivity별 악화 경계와 회복 경계
- 악화·회복·장시간 평가 불가에 필요한 버스트 수

ROI 크기 비례 계수(어깨 너비 기준)는 기하 설계값으로 `PostureFrameAnalyzer`에 두며, 위와 같이 제품 데이터 검증 대상이다.

DA-V2 방향은 현재 `largerIsNear`로 명시되어 있다. 코드 테스트는 방향 설정이 feature 부호를 정확히 바꾸는지만 검증한다. 실제 Apple Core ML 모델의 전처리까지 포함한 near/far 방향은 가까운 물체와 먼 물체가 명확한 고정 fixture로 별도 확인해야 한다. 이 실측 전에는 임계값과 자세 판정 성능을 확정된 것으로 간주하지 않는다.

## 검증 명령

```sh
Tests/run.sh
swift build --disable-sandbox
```

테스트는 affine scale·shift 불변성, 품질 실패, 대상 모호성, 3~5장 버스트 집계, 여러 보정 버스트, 상태 지속성, 최소 점검 주기, debug 파일명과 `session.json`의 제품 상태·프레임 진단·처리 시간, local RGB-depth 쌍 선택을 직접 확인한다. 실제 카메라 안정화, Core ML near/far 방향과 prod/debug의 처리 시간 영향은 고정 fixture와 장치 통합 검증이 추가로 필요하다.
