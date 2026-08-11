# 목바로

목바로는 macOS 메뉴 막대에서 내장 카메라로 바른 자세 습관을 돕는 알림 앱이다.
머리를 앞으로 내밀거나, 등을 구부리거나, 고개를 기울이는 등 사용자가 저장한 기준 자세에서 벗어난 상태가 이어지면 알려 준다.

모든 분석은 기기 안에서 처리한다.
일반 실행에서는 카메라 이미지를 저장하거나 외부로 보내지 않고 자세 이벤트 통계와 설정만 기기에 남긴다.
임상 각도가 아니라 사용자가 저장한 기준 자세와의 차이로 판정하며 알고리즘이나 민감도를 따로 고르는 설정은 없다.

## 동작 원리

한 번의 점검은 최대 5장의 이미지를 짧게 연속 촬영해 처리하고 결과를 정상, 악화, 판정 불가로 나눈다.

| 단계 | 역할 | 모델과 환경 |
|---|---|---|
| 2D 상체 추정 | 머리와 어깨 랜드마크·신뢰도 추출 | Apple 공식 샘플 PoseNet 우선, 사용할 수 있는 상체 후보가 없으면 Apple Vision 2D 사용 |
| 상대 깊이 | 머리와 몸통 ROI의 상대 깊이 특성값 생성 | Depth Anything V2 Small(Core ML) |
| 최종 판정 | 저장된 기준 자세와 여러 프레임의 대표값 비교 | 기기 내부 |

머리는 보이지만 턱을 괴거나 기울이거나 숙여 정상인지 확인할 수 없는 프레임이 최소 2개이면서 수집한 프레임의 과반이면 악화로 처리한다.
사람이 없거나 기술적 입력이 부족하면 판정 불가로 처리한다.

저장된 기준 자세가 없으면 앱을 시작할 때 보정을 먼저 진행한다.
앱이 보정 필요를 표시하거나 카메라·화면 구도가 바뀌면 바른 자세에서 **보정**을 다시 실행한다.
호환되지 않는 구버전 기준 자세도 사용하지 않고 새 보정을 요구한다.
잘못된 자세를 기준으로 저장하면 바르게 앉아도 기준과 다르다고 판정할 수 있다.

### 문서 구분

- [목바로 제품 문서](docs/ko/README.md) / [turtlemeck product documentation](docs/README.md): 메뉴 막대 화면, 보정과 점검, 설정, 알림, 개인정보, 아키텍처, 디버깅
- [채택 기술 문서](docs/workflow.md): 현재 코드가 따르는 자세 분석 흐름과 `algorithm/`, `depth-estimation/`의 채택 근거
- [한국어 리서치 보관소](docs/research/): 조사했지만 현재 코드에 채택하지 않은 자료와 과거 검토 기록

## 요구 사항

- macOS 15 이상, macOS Tahoe 26 이상 권장
- Command Line Tools의 Swift 6.0 이상, Swift 6.3 이상 권장
- Xcode 전체 설치 불필요

## 개발

모든 작업은 `make`로 실행한다.
전체 명령어는 `make help`에서 확인한다.

| 명령어 | 설명 |
|---|---|
| `make check` | Swift 테스트 러너(`Tests/run.sh`)와 `swift build`로 검증 |
| `make package` | Universal2 `.app`을 만들고 ad-hoc 서명한 뒤 ZIP과 DMG 생성 |
| `make run` | 메뉴 막대 모드로 실행하며 앱 번들이 없으면 먼저 패키징 |
| `make run-fresh` | 설정과 기준 자세를 초기화하고 다시 패키징해 새 인스턴스로 실행 |
| `make run-debug` | 초기화 후 `--debug` 창 모드로 실행하고 디버그 패널과 `debug/` 산출물 활성화 |
| `make stop` | 실행 중인 앱 종료 |

### 검증

```bash
make check
```

일부 제한된 환경에서는 SwiftPM의 `sandbox-exec`와 충돌할 수 있어 빌드에 `--disable-sandbox`를 사용한다.

### 실행

```bash
make run        # 메뉴 막대 모드
make run-debug  # 디버그 창 모드
```

일반 사용에는 메뉴 막대 모드를 사용한다.
개발하거나 카메라 입력을 확인할 때는 `make run-debug`를 사용한다.
디버그 모드는 메뉴 막대 아이콘 대신 크기를 조절할 수 있는 창에 같은 `MenuView`와 디버그 정보 패널을 표시하고 검증용 이미지와 JSON을 `debug/`에 남긴다.
일반 실행과 디버그 실행은 같은 자세 판정, 설정, 통계 경로를 사용한다.

`run-fresh`와 `run-debug`는 UserDefaults의 설정과 기준 자세만 초기화한다.
일일 통계 파일과 기존 `debug/` 산출물은 지우지 않는다.
카메라 권한 상태가 미결정이면 첫 보정을 시작할 때 macOS가 권한을 요청한다.

### 패키징

```bash
make package
```

기본 `make package`는 `.build/turtlemeck.app`을 Universal2로 만들고 ad-hoc 서명한 뒤 `.build/turtlemeck.zip`과 `.build/turtlemeck.dmg`를 생성한다.
`vMAJOR.MINOR.PATCH` 태그 릴리스는 `.github/workflows/release.yml`에서 태그 버전과 빌드 번호를 주입하고 Developer ID 서명과 Apple 공증을 거쳐 `turtlemeck-<version>.dmg`, ZIP, SHA-256 체크섬을 GitHub Release에 첨부한다.
실행 전에 저장소 Actions 시크릿으로 base64로 인코딩한 Developer ID Application P12 `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, 앱 전용 암호 `APPLE_PASSWORD`, `APPLE_TEAM_ID`를 설정해야 한다.

## 프로젝트 구조

핵심 로직은 `Sources/TurtleCore` 아래에서 역할별로 나뉜다.

| 모듈 | 책임 |
|---|---|
| `App/` | 앱 수명 주기와 상태 조율(`AppModel`) |
| `Camera/` | 카메라 세션, 연속 촬영 타이밍, 프레임 품질 게이트 |
| `Inference/` | Core ML 추론 어댑터(PoseNet, Vision 2D, Depth Anything V2) |
| `Detection/` | 프레임 분석, 여러 프레임 집계, 보정, 상태 전이, 상체 기하 |
| `MenuBar/` | 메뉴 막대와 창 모드 UI |
| `Notifications/` | 알림 시점과 반복 제한 정책 |
| `Output/` | 판정에 사용하지 않는 디버그·로컬 산출물 기록 |
| `Storage/` | 설정, 기준 자세, 일일 통계 저장 |

각 모듈의 역할과 구현 경계는 [자세 분석 구현 결정](docs/posture-analysis/README.md)에 정리돼 있다.
