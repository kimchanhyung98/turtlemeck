# 목바로

목바로는 macOS 메뉴 막대에 상주하면서 내장 카메라로 바른 자세를 지키도록 돕는 알림 앱입니다. 전방머리(거북목)나 구부정하게 앉거나 고개를 기울인 자세처럼, 직접 저장해 둔 기준 자세에서 벗어난 상태가 이어지면 알려 줍니다.

모든 분석은 기기 안에서만 이뤄집니다. 카메라 이미지를 저장하거나 밖으로 보내지 않고, 평소 사용에서는 자세 이벤트 통계와 설정만 기기에 남습니다. 판정은 임상적으로 정해진 각도가 아니라 직접 보정한 기준 자세와 얼마나 다른지로 하며, 사용자가 알고리즘이나 민감도를 따로 고를 필요가 없습니다.

## 동작 원리

한 번의 점검은 3~5장의 짧은 이미지 버스트를 찍어 아래 순서로 처리한 뒤, 결과를 정상, 비정상, 판정 불가 세 가지로 나눕니다.

| 단계 | 역할 | 모델과 환경 |
|---|---|---|
| 2D 상체 추정 | 머리와 어깨 landmark, confidence 추출 | Apple 공식 샘플 PoseNet 우선, 실패 시 Apple Vision 2D |
| 상대 깊이 | 머리와 몸통 ROI의 relative depth feature 생성 | Depth Anything V2 Small (Core ML) |
| 최종 판정 | 저장된 기준 자세와 버스트 대표값 비교 | 기기 내부 |

머리는 보이지만 턱을 괴거나 기울이거나 숙여서 정상인지 확인할 수 없으면 비정상으로, 사람이 아예 없으면 판정 불가로 처리합니다.

기준 자세가 저장돼 있지 않으면 앱을 켤 때 보정을 먼저 진행합니다. 그 뒤로는 카메라 각도나 앉은 거리가 달라졌을 때만 바른 자세에서 "보정"을 다시 누르면 됩니다. 잘못된 자세를 기준으로 저장하면 바르게 앉아도 다르다고 판정할 수 있으니 주의하세요.

### 상세 문서

판단 순서와 임계값, 모델을 고른 근거는 `docs/`에 정리해 두었습니다.

- [자세 분석 워크플로우 개론](docs/workflow.md): 전체 흐름과 하위 문서 목록이라 여기서 시작하면 됩니다.
- [자세 분석 상세 워크플로우](docs/algorithm/posture-analysis-workflow.md): 캡처부터 상태 전이와 알림까지의 판단 순서, 실패 처리
- [자세 분석 구현 결정](docs/posture-analysis/README.md): 모듈 경계와 잠정 튜닝값, 장치 검증 이력
- [2D 자세 모델 비교](docs/algorithm/pose-estimation/comparison.md)와 [Depth Anything V2 분석](docs/depth-estimation/depth-anything-v2/analysis.md): 모델을 고른 근거

## 요구사항

- macOS Tahoe 26 이상 권장
- Command Line Tools Swift 6.3 이상 (Xcode는 필요 없습니다)

## 개발

모든 작업은 `make`로 합니다. 전체 명령어는 `make help`로 볼 수 있습니다.

| 명령어 | 설명 |
|---|---|
| `make check` | Swift 테스트 러너(`Tests/run.sh`)와 `swift build`로 검증 |
| `make package` | Universal2 `.app`을 만들어 ad-hoc 서명하고 ZIP과 DMG 생성 |
| `make run` | 메뉴 막대 모드로 실행 (앱 번들이 없으면 먼저 패키징) |
| `make run-fresh` | 설정과 baseline을 초기화하고 다시 패키징해 새 인스턴스로 실행 |
| `make run-debug` | 초기화 후 `--debug` 창 모드로 실행 (디버그 패널과 `debug/` 산출물) |
| `make stop` | 실행 중인 앱 종료 |

### 검증

```bash
make check
```

일부 제한된 환경에서는 SwiftPM의 `sandbox-exec`와 충돌할 수 있어 빌드에 `--disable-sandbox`를 씁니다.

### 실행

```bash
make run        # 메뉴 막대 모드
make run-debug  # 디버그 창 모드
```

평소에는 메뉴 막대 모드로 실행합니다. 개발하거나 카메라를 확인할 때는 `make run-debug`를 씁니다. 이 모드는 메뉴 막대 아이콘 대신 크기를 조절할 수 있는 창에 같은 `MenuView`와 디버그 정보 패널을 함께 띄우고, 검증용 이미지와 JSON을 `debug/`에 남깁니다. 일반 실행과 디버그 실행은 자세 판정과 설정, 통계 경로를 똑같이 씁니다.

`run-fresh`와 `run-debug`는 UserDefaults의 설정과 baseline만 초기화하고, 일일 통계 파일이나 `debug/` 산출물은 지우지 않습니다. 처음 실행할 때는 카메라 권한이 필요합니다.

### 패키징

```bash
make package
```

`.build/turtlemeck.app`을 Universal2로 만들어 ad-hoc 서명한 뒤 `.build/turtlemeck.zip`과 `.build/turtlemeck.dmg`를 생성합니다. `hdiutil create`가 막힌 환경에서는 hybrid DMG로 대신합니다. Developer ID 공증은 아직 범위 밖입니다.

## 프로젝트 구조

핵심 로직은 `Sources/TurtleCore` 아래에 역할별 모듈로 나뉘어 있습니다.

| 모듈 | 책임 |
|---|---|
| `App/` | 앱 수명주기와 상태 조율(`AppModel`) |
| `Camera/` | 카메라 세션, 버스트 타이밍, 프레임 품질 게이트 |
| `Inference/` | Core ML 추론 어댑터 (PoseNet, Vision 2D, Depth Anything V2) |
| `Detection/` | 자세 판정 로직: 프레임 분석기, 버스트 집계, 보정, 상태 전이, 상체 기하 |
| `MenuBar/` | 메뉴 막대와 창 모드 UI |
| `Notifications/` | 알림 시점과 반복 제한 정책 |
| `Output/` | debug와 local 산출물 기록 (판정에는 쓰지 않음) |
| `Storage/` | 설정과 baseline, 일일 통계 저장 |

각 모듈의 역할 분담과 구현 경계는 [자세 분석 구현 결정](docs/posture-analysis/README.md)에 정리돼 있습니다.
