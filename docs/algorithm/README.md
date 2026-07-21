# 알고리즘 문서 안내

> 이 문서는 참고용 리서치이며, 현재 확정된 제품 플로우를 직접 정의하거나 구현 기준으로 활용하지 않습니다.

이 디렉토리는 확정 설계를 뒷받침하는 알고리즘 리서치를 관리한다. 현재 코드가 문서의 결정을 바꾸는 근거가 되지 않으며, 리서치 문서가 곧바로 구현 기준이 되지도 않는다.

## 문서 우선순위

| 우선순위 | 문서 | 역할 |
|---:|---|---|
| 1 | [posture-analysis-workflow.md](posture-analysis-workflow.md) | 전체 처리 순서, 상세 판단 로직과 채택·제외 범위를 정의하는 규범 문서 |
| 2 | [../workflow.md](../workflow.md) | 제품 플로우와 역할 분담을 빠르게 이해하기 위한 개론 |
| 3 | [apple-body-pose/checklist.md](apple-body-pose/checklist.md) | 목표 설계가 구현 단계에서 지켜졌는지 확인하는 비규범 체크리스트 |
| 4 | [apple-posenet/](apple-posenet/README.md) | Apple Core ML 샘플 PoseNet의 모델·decoder·통합 경계 리서치 |
| 4 | [apple-body-pose/](apple-body-pose/README.md) | Apple Vision API의 제공 정보와 한계에 관한 리서치 |
| 4 | [pose-estimation/](pose-estimation/README.md) | 자세 추정 모델·기하·baseline·단안 한계에 관한 리서치 |
| 4 | [../depth-estimation/](../depth-estimation/README.md) | 단안 깊이 모델과 자세 신호 적용 가능성에 관한 리서치 |

내용이 충돌하면 상세 규범 문서인 `posture-analysis-workflow.md`를 우선한다. 상위 `workflow.md`는 개론이므로 상세 판단을 새로 정의하거나 하위 문서의 결정을 바꾸지 않는다. 리서치 결과로 목표 설계를 바꿀 때는 리서치 문서를 구현 기준으로 직접 사용하지 않고, 먼저 상세 워크플로우를 수정한 뒤 개론을 동기화한다.

## 알고리즘·방식별 공통 파일

독립적인 알고리즘이나 처리 방식은 `kebab-case` 디렉토리 하나로 묶고 다음 세 파일을 공통으로 사용한다.

| 파일명 | 필수 여부 | 역할 |
|---|---|---|
| `README.md` | 필수 | 상태·요약·입력/출력·간단한 처리 흐름·제품 적용 판단·문서 목록 |
| `analysis.md` | 필수 | 로직 구성, 단계별 처리, 수식·좌표계·API, 기술적 한계의 분석과 설명 |
| `references.md` | 필수 | 공식 문서, 논문, 추가·관련 자료, 근거 수준 |
| `validation.md` | 선택 | 데이터셋, 측정 프로토콜, 합격 기준, 검증 결과 |
| `comparison.md` | 선택 | 같은 역할을 수행하는 대안들의 동일 기준 비교 |
| `checklist.md` | 선택 | 구현·문서가 확정 설계와 일치하는지 확인하는 항목 |
| `related-<topic>.md` | 선택 | 핵심 로직 분석과 분리해서 유지할 교차 연구·배경 자료 |

`README.md`는 진입점이므로 상세 로직 분석이나 긴 출처 목록을 중복하지 않는다. `analysis.md`와 `references.md`의 결론만 요약하고 링크한다. 선택 파일은 실제 내용이 있을 때만 만들며, 빈 형식을 맞추기 위해 생성하지 않는다.

인덱스 디렉토리, 규범 문서, 프로젝트 전체 체크리스트와 인덱스 직속 교차 연구 모음(`etc/`)은 독립 알고리즘이 아니므로 이 세 파일 규칙의 예외다. 예외 여부는 상위 README의 문서 구성 표에 명시한다.

## 파일명 규칙

- 디렉토리와 선택 파일은 소문자 `kebab-case` 영문명을 사용한다.
- `README.md`만 대문자 고정 이름을 사용한다.
- 날짜, 버전, 상태(`draft`, `final`, `new`)를 파일명에 넣지 않는다. 필요한 상태는 문서 본문에 기록한다.
- `overview.md`, `details.md`, `notes.md`, `misc.md`처럼 역할이 겹치거나 범위가 불명확한 이름은 사용하지 않는다.
- 독립적인 방식은 임의의 단일 Markdown 파일로 추가하지 않고 `<method>/README.md`에서 시작한다.
- 관련 자료는 `references.md`, 대안 비교는 `comparison.md`, 실측은 `validation.md`로만 분리한다.
- 별도 설명이 필요한 교차 연구만 `related-<topic>.md`로 만들며, `<topic>`에는 문서 내용을 드러내는 구체적인 명사를 쓴다.

## 공통 문서 형식

### `README.md`

1. 문서 요약 표: 문서 유형, 적용 상태, 입력, 출력, 제품 내 역할
2. 요약 플로우: 입력 → 처리 → 출력이 드러나는 작은 다이어그램 또는 순서 목록
3. 제품 적용 판단: 채택·보조·검증 필요·미채택·제외
4. 한계와 검증 상태
5. 문서 구성: 같은 디렉토리의 공통 파일 링크

### `analysis.md`

1. 목적과 전제
2. 입력과 출력의 정확한 정의
3. 처리 단계별 로직 분석
4. 좌표계·수식·API 등 세부 원리
5. 알려진 한계와 실패 조건
6. 제품 적용 시 지켜야 할 경계

### `references.md`

1. 핵심 근거 표: 주장, 출처, 근거 수준
2. 공식 문서와 1차 연구
3. 추가·관련 자료
4. 제품 환경에 직접 적용할 수 없는 내용과 이유

### 선택 파일

- `validation.md`: 목표 → 데이터 → 절차 → 지표 → 합격 기준 → 결과 순서로 작성한다.
- `comparison.md`: 동일한 평가 열을 쓰는 표로 작성하고 현재 선택과 미채택 이유를 명시한다.
- `checklist.md`: 각 항목을 검증 가능한 단일 문장으로 작성하고 근거 문서에 연결한다.
- `related-<topic>.md`: 문서 요약 → 핵심 근거 → 현재 방식과의 관계 → 적용하지 않는 범위 → 참고 자료 순서로 작성한다.

## 적용 상태 용어

| 상태 | 의미 |
|---|---|
| 채택 | 현재 목표 제품 플로우에 포함 |
| 보조 | 채택 경로의 입력 품질이나 ROI 등을 지원하지만 단독 판정에는 사용하지 않음 |
| 검증 필요 | 제품 데이터 측정 전에는 채택 여부를 결정할 수 없음 |
| 미채택 | 조사했지만 현재 확정된 제품 플로우에는 사용하지 않으며 리서치 자료로만 유지 |
| 제외 | 현재 목표 제품 플로우에 사용하지 않음 |
| 근거 문서 | 런타임 로직이 아니라 채택 범위·한계·용어를 뒷받침 |

한 문서에 여러 기술이 포함되면 `부분 채택`처럼 뭉뚱그리지 않고 기술별 상태를 문서 요약이나 적용 판단 표에서 나눠 적는다.

## 현재 문서 구성

```text
algorithm/
├── README.md                         # 문서 체계와 상태 용어
├── posture-analysis-workflow.md      # 규범: 상세 처리·판정 로직과 제외 범위
├── apple-posenet/
│   ├── README.md                     # Apple Core ML 샘플 PoseNet 진입점
│   ├── analysis.md                   # 모델 I/O·decoder·좌표계 분석
│   └── references.md                 # Apple 샘플·TensorFlow·로컬 근거
├── apple-body-pose/
│   ├── README.md                     # Apple Vision 리서치 진입점
│   ├── analysis.md                   # Vision 2D body pose 분석
│   ├── related-vision-3d.md          # Vision 3D 분석과 제외 근거
│   ├── related-person-observations.md # face·person mask 경계
│   ├── references.md                 # 공식·관련 자료
│   └── checklist.md                  # 설계 적합성 검증
└── pose-estimation/
    ├── README.md                     # 자세 추정 리서치 진입점
    ├── analysis.md                   # 모델·feature·판정 로직 분석
    ├── references.md                 # 공식·관련 자료
    ├── comparison.md                 # 대안 모델 비교
    ├── related-cva-metrics.md
    ├── related-monocular-limits.md
    ├── related-viewpoint-geometry.md
    └── related-baseline-calibration.md
```
