# turtlemeck

macOS 메뉴 막대에 상주하며 내장 카메라로 바른 자세 유지를 돕는 알림 앱입니다.
전방머리(거북목)·구부정 등 "바른 자세가 아닌" 상태를 감지해 알립니다.

## 요구사항

- macOS Tahoe 26 이상 권장
- Command Line Tools Swift 6.3 이상
- Xcode 불필요

## 검증

```bash
make check
```

`make check`는 커스텀 Swift 테스트 러너(`scripts/run-tests.sh`)와 `swift build --disable-sandbox`를 실행합니다. 
일부 제한된 실행 환경에서는 SwiftPM의 자체 `sandbox-exec`와 충돌할 수 있어 `--disable-sandbox`를 사용합니다.

## 앱 빌드

```bash
make package
```

`.build/turtlemeck.app`을 Universal2로 조립하고 ad-hoc 서명한 뒤 `.build/turtlemeck.zip`과 `.build/turtlemeck.dmg`를 만듭니다.
`hdiutil create`가 제한된 환경에서는 hybrid DMG로 대체합니다. Developer ID 공증은 현재 범위가 아닙니다.

## 실행

```bash
make run
```

`make run`은 기존 `.build/turtlemeck.app`을 실행합니다. 앱 번들이 없으면 한 번 패키징합니다.
소스 변경까지 반영해 새로 띄우려면 다음 명령을 사용합니다.

```bash
make run-fresh
```

`make run-fresh`는 기존 실행 앱을 종료하고 새로 패키징한 뒤 새 인스턴스로 앱을 엽니다. 최초 실행 시 카메라 권한이 필요합니다.
영상은 저장되거나 전송되지 않으며, 자세 이벤트 통계와 설정만 로컬에 저장됩니다.

기본 실행은 메뉴 막대 모드다. 개발·카메라 검증 중에는 디버그 모드를 사용한다.

```bash
make run-debug
```

`make run-debug`는 기존 실행 앱을 종료하고 `--debug` 플래그로 앱을 실행한다. 디버그 모드는 메뉴 막대 아이콘 대신 360×680 크기의 일반 창에 같은 `MenuView`를 표시하고 debug 정보 패널을 함께 켠다. `지금 점검`, `일시정지`, `재보정`, 설정과 debug 정보는 세로로 스크롤할 수 있다. 두 모드는 자세 분석과 저장 데이터를 공유하며 표시 방식만 다르다. 실행 중인 앱만 종료하려면 `make stop`을 사용한다.

## AI/ML 분석 방식

메뉴 막대 팝오버 상단에 현재 측정값(신호 종류·값·신뢰도·시점)이 표시되며, "AI/ML 분석 방식"에서 사용할 ML 경로를 전환할 수 있습니다. 기하 기반 판정 방식은 회귀 테스트와 내부 fallback 검증용으로 남아 있지만, 제품 UI에는 노출하지 않습니다.

| 방식 | 신호 | 동작 환경 |
|---|---|---|
| AI/ML 자동(기본) | Core ML 상대깊이 + Apple Vision 3D 중 가용 신호 자동 선택 | Apple Silicon 권장 |
| Core ML Depth Anything | Depth Anything V2 Small 상대깊이 | 전 기종(Core ML) |
| Apple Vision 3D 깊이차 | Vision 3D pose의 머리-몸통 전방 깊이차 | Apple Silicon |
| Apple Vision 3D 신체축 | Vision 3D pose의 신체 좌표계 시상각 | Apple Silicon |

- **Apple Vision 3D 기반 방식은 Apple Silicon에서만 동작**하며, 미지원 환경에서는 해당 신호가 자동 보류(noEval)됩니다.
- **Core ML Depth Anything V2 Small 모델은 앱 번들에 포함**됩니다. 절대 cm 측정이 아니라 개인 기준자세 대비 상대 변화 신호로만 사용합니다.
- 정면 카메라는 기준 자세(baseline) 보정이 있어야 상대 판정이 정확합니다. 좋은 자세에서 메뉴의 **"재보정"**을 한 번 실행하는 것을 권장합니다.
- 현재 판정 임계·가중치는 잠정값이며, 실측 데이터 기반 튜닝이 필요한 개발 단계입니다.
