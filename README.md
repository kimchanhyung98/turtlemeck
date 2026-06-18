# turtlemeck

macOS 메뉴 막대에 상주하며 내장 카메라로 전방머리/구부정 자세 징후를 온디바이스에서 추정하는 일반 웰니스 자세 알림 앱입니다.

## 요구사항

- macOS Tahoe 26 이상 권장
- Command Line Tools Swift 6.3 이상
- Xcode 불필요

## 검증

```bash
make check
```

`make check`는 커스텀 Swift 테스트 러너(`scripts/run-tests.sh`)와 `swift build --disable-sandbox`를 실행합니다. 이 환경에서는 SwiftPM의 자체 `sandbox-exec`가 Codex 샌드박스와 충돌하므로 `--disable-sandbox`를 사용합니다.

## 앱 빌드

```bash
make package
```

`.build/turtlemeck.app`을 Universal2로 조립하고 ad-hoc 서명한 뒤 `.build/turtlemeck.zip`과 `.build/turtlemeck.dmg`를 만듭니다. `hdiutil create`가 제한된 환경에서는 hybrid DMG로 대체합니다. Developer ID 공증은 현재 범위가 아닙니다.

## 실행

```bash
make run
```

최초 실행 시 카메라 권한이 필요합니다. 영상은 저장되거나 전송되지 않으며, 자세 이벤트 통계와 설정만 로컬에 저장됩니다.
