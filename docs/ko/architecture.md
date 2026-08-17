# 아키텍처

코드를 다루는 사람을 위해 목바로(`turtlemeck`)의 앱 구성과 데이터 흐름을 정리한 문서다.
사용자에게 보이는 동작은 [목바로 문서](README.md)에서 먼저 확인한다.

## 앱 형태

목바로는 서버나 웹 화면이 없는 네이티브 macOS 앱이다.
일반 실행에서는 `LSUIElement` 메뉴 막대 앱으로 동작하고 Dock 아이콘이나 기본 창을 만들지 않는다.
`--debug` 실행에서는 메뉴 막대 아이콘 대신 크기를 조절할 수 있는 일반 창에 같은 SwiftUI 화면과 디버그 정보를 표시한다.

Swift Package에는 외부 패키지 의존성이 없고 다음 제품과 실행형 타깃이 있다.

| 구성 요소 | 역할 |
|---|---|
| `TurtleCore` | 앱, 카메라, 추론, 판정, 알림, 저장 로직을 담은 라이브러리 |
| `turtlemeck` | macOS 앱 실행 진입점 |
| `analyze-image` | 저장 이미지의 2D 자세·상대 깊이 특성값을 확인하는 개발 도구 |
| `workflow-tests` | SwiftPM 실행형 테스트 러너 |

## 구성 루트

`Sources/turtlemeck/main.swift`가 `runTurtleMeckApp()`을 호출한다.
`Sources/TurtleCore/App/Entry.swift`에 정의된 이 함수가 `AppDelegate`를 생성·유지하고 설치한다.
`AppDelegate`는 하나의 `AppModel`을 만들고 실행 모드에 따라 `StatusItemController` 또는 디버그 `NSWindow`에 연결한다.

`AppModel`은 화면 상태를 소유하며 다음 구성 요소의 수명 주기를 조율한다.

- `CameraManager` — 카메라 예약, 캡처, 추론·판정 파이프라인 실행
- `SettingsStore`, `StatsStore` — 기준 자세·설정과 날짜별 통계 저장
- `PostureStateMachine` — 자세 증거에 지속성 규칙을 적용해 `good`·`bad`·`noEval` 전이와 이벤트 생성. 나머지 수명 주기 상태는 `AppModel`이 소유
- `NotificationPolicy`, `NotificationManager` — 반복 제한, 스누즈, 배너·소리 출력

카메라 계층의 콜백은 판정, 다음 점검 시각, 카메라 차단, 진단, 캡처 활성 상태를 `AppModel`에 전달한다.
화면은 `AppModel`이 게시한 상태를 관찰한다.

## 분석 흐름

한 번의 점검은 다음 순서로 진행된다.

1. `CameraManager`가 내장 카메라를 640×480으로 열고 워밍업 뒤 최대 5프레임을 고른다.
2. `PoseDetector`가 PoseNet을 우선 사용하고 사용할 수 있는 상체 후보가 없으면 Apple Vision 2D를 사용한다.
3. `CoreMLRelativeDepthProvider`가 Depth Anything V2 Small로 상대 깊이 맵을 만든다.
4. `UpperBodySubjectSelector`가 한 명의 후보를 고르고, `PostureFrameAnalyzer`가 그 사람의 머리·몸통·참조 ROI에서 기준과 비교할 특성값을 만든다.
5. `BurstProcessor`가 프레임 중앙값과 품질을 집계하고 저장된 기준 자세와 비교한다.
6. `PostureStateMachine`이 정상·악화·판정 불가 증거에 지속성 규칙을 적용해 `good`·`bad`·`noEval` 전이와 주의·회복 이벤트를 만든다.
7. `AppModel`이 화면과 통계를 갱신하고 `NotificationPolicy`가 허용한 주의 이벤트만 알린다.

디버그·로컬 출력은 제품 상태가 결정된 뒤 별도 출력 큐에서 기록한다.
출력 지연이나 실패, 로컬 AI 결과는 판정의 입력으로 돌아가지 않는다.
자세한 판정 계약은 [자세 분석 워크플로우](../workflow.md)에서 확인한다.

## 소스 구성

| 디렉터리 | 책임 |
|---|---|
| `Sources/TurtleCore/App/` | 앱 수명 주기, 실행 모드, 화면 상태 조율 |
| `Sources/TurtleCore/Camera/` | 권한, 캡처 세션, 버스트 예약, 프레임 품질 게이트 |
| `Sources/TurtleCore/Inference/` | PoseNet·Depth Anything V2 Core ML 어댑터와 Apple Vision 2D 폴백 |
| `Sources/TurtleCore/Detection/` | 대상 선택, ROI·특성값, 보정, 버스트 판정, 상태 전이, 튜닝값 |
| `Sources/TurtleCore/MenuBar/` | `NSStatusItem`, `NSPopover`, 공용 SwiftUI `MenuView` |
| `Sources/TurtleCore/Notifications/` | 알림 반복 정책과 macOS 배너·소리 출력 |
| `Sources/TurtleCore/Storage/` | UserDefaults 설정·기준 자세와 JSON 일일 통계 |
| `Sources/TurtleCore/Output/` | 판정에 영향을 주지 않는 디버그·로컬 산출물 |
| `Sources/TurtleCore/Launch/` | `SMAppService` 로그인 항목 상태 조회·등록·해제 |

## 상태와 영속성

| 상태 | 소유자 | 영속 여부 |
|---|---|---|
| 현재 자세 상태, 다음 점검, 일시정지 | `AppModel` | 앱을 다시 실행하면 초기 상태로 돌아감 |
| 악화·회복·판정 불가 연속 횟수 | `PostureStateMachine` | 메모리에만 유지 |
| 알림 최소 간격과 스누즈 | `NotificationPolicy` | 메모리에만 유지 |
| 점검 주기, 알림 설정, 기준 자세 | `SettingsStore` | UserDefaults에 저장하며 `--debug` 실행 여부는 저장하지 않음 |
| 날짜별 정상·주의 시간과 이벤트 수 | `StatsStore` | `Application Support/turtlemeck/stats.json`에 저장 |

로그인 시 자동 실행은 저장된 설정만 신뢰하지 않고 앱 시작 때 `SMAppService.mainApp`의 실제 등록 상태를 다시 읽는다.

## AppKit 브리지

일반 모드의 `StatusItemController`는 `NSStatusItem`과 `.transient` 동작의 `NSPopover`를 소유하고 그 안에 SwiftUI `MenuView`를 호스팅한다.
팝오버 밖의 로컬·전역 마우스 입력을 감시해 화면을 닫지만 앱의 점검은 멈추지 않는다.

디버그 모드에서는 `NSWindow` 안의 `NSHostingController`가 같은 `MenuView`를 `ScrollView`로 감싼다.
디버그 실행 플래그는 별도로 `MenuView`, `AppModel`, `CameraManager`를 통해 진단 패널과 파일 출력도 활성화한다.
자세 판정, 설정, 통계 경로는 일반 모드와 같다.

## 플랫폼과 패키징

배포 대상의 최소 버전은 macOS 15이며 Swift Package의 최소 도구 버전은 Swift 6.0이다.
개발에는 macOS Tahoe 26과 Swift 6.3을 권장하고 CI는 별도 Swift 도구 모음을 고정하지 않은 `macos-26`에서 실행한다.
기본 `package.sh`는 arm64와 x86_64 릴리스 바이너리를 합친 Universal2 `.app`을 만들고 ad-hoc 서명한 뒤 ZIP, DMG, SHA-256 체크섬을 생성한다.
`vMAJOR.MINOR.PATCH` 태그 릴리스는 `.github/workflows/release.yml`에서 태그 버전과 빌드 번호를 주입하고 카메라 접근 권한(`com.apple.security.device.camera`)을 포함한 Developer ID 서명과 Apple 공증을 강제한 뒤 버전을 표시한 DMG, ZIP, SHA-256 체크섬을 GitHub Release에 첨부한다.
이 워크플로는 저장소 Actions 시크릿의 `APPLE_CERTIFICATE`에서 base64로 인코딩한 Developer ID Application P12를, `APPLE_CERTIFICATE_PASSWORD`에서 P12 암호를, `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`에서 공증 계정과 앱 전용 암호, 팀 ID를 읽는다.

PoseNet과 Depth Anything V2 모델은 앱 리소스에 포함한다.
앱 자체에는 서버, 수신 포트, 네트워크 요청 경로가 없다.
