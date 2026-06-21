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

`make run`은 기존 실행 앱을 종료하고 새로 패키징한 뒤 앱을 엽니다. 최초 실행 시 카메라 권한이 필요합니다. 
영상은 저장되거나 전송되지 않으며, 자세 이벤트 통계와 설정만 로컬에 저장됩니다.

## 자세 판정 알고리즘

메뉴 막대 팝오버 상단에 현재 측정값(신호 종류·값·신뢰도·시점)이 표시되며, "판정 알고리즘"에서 5가지 추정 로직을 즉시 전환할 수 있습니다.

| 알고리즘      | 신호                 | 동작 환경         |
|-----------|--------------------|---------------|
| 측면 기하     | 측면/3-4 머리-어깨 단조 각  | 전 기종          |
| 정면 보조     | 정면 어깨폭 정규화 추세(약신호) | 전 기종          |
| 3D 시상각    | 신체중심 좌표 머리-몸통 각    | Apple Silicon |
| 3D 깊이차    | 이마-몸통 전방 깊이차       | Apple Silicon |
| 적응 융합(기본) | 시점·환경별 자동 선택       | 전 기종          |

- **3D 기반 두 알고리즘(3D 시상각·3D 깊이차)은 Apple Silicon에서만 동작**하며, 미지원 환경에서는 해당 신호가 자동 보류(noEval)됩니다. 
기본값인 적응 융합은 환경에 맞춰 자동으로 2D 경로로 대체됩니다.
- 정면 카메라는 기준 자세(baseline) 보정이 있어야 상대 판정이 정확합니다. 좋은 자세에서 메뉴의 **"재보정"**을 한 번 실행하는 것을 권장합니다.
- 현재 판정 임계·가중치는 잠정값이며, 실측 데이터 기반 튜닝이 필요한 개발 단계입니다.
