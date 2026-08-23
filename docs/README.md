# 목바로 문서

이 디렉터리는 목바로의 현재 기능과 동작을 설명한다.
최상위 Markdown 문서는 앱 구현·정책·화면을 다루고, `posture-analysis/`는 현재 채택한 자세 분석 알고리즘과 AI 모델의 동작 계약을 기록한다.
조사 여부나 채택 여부와 관계없이 리서치 과정에서 만든 자료는 `.research/`에 보존한다.
앱과 문서의 설명이 다르면 버그로 본다.

한국어 제품명은 목바로다.
저장소 경로, 앱 번들, 실행 파일 이름, 시스템용 식별자에는 기술 식별자 `turtlemeck`을 유지한다.

## 현재 제품 문서

### 앱

- [메뉴 막대](menu-bar.md) — 상태 아이콘, 팝오버, 빠른 동작, 오늘 요약
- [기준 자세 보정과 점검](posture-checks.md) — 첫 실행, 보정, 정기·즉시 점검, 상태 전환
- [설정](settings.md) — 모든 사용자 설정과 각 설정이 바꾸는 동작
- [알림](notifications.md) — 배너와 소리, 반복 제한, 20분 스누즈
- [개인정보와 로컬 데이터](privacy.md) — 카메라·알림 권한, 저장 데이터, 디버그·로컬 모드 예외

### 개발자용

- [아키텍처](architecture.md) — 앱 형태, 구성 루트, 분석 흐름, 저장소, 플랫폼 연동
- [디버깅](debugging.md) — 로컬 빌드와 실행, 디버그 창, 환경 변수, 산출물

## 자세 분석

- [자세 분석 구현 결정](posture-analysis/README.md) — 구현에 반영된 모듈 경계, 조정값, 장치 검증 기록
- [자세 분석 워크플로우](posture-analysis/workflow.md) — 현재 코드가 구현한 제품 흐름과 판정 규범
- [상세 판정 알고리즘](posture-analysis/algorithm.md) — 캡처, 특성값, 기준 자세 비교, 상태 전이 계약
- [PoseNet과 Vision 2D](posture-analysis/posenet.md) — 상체 랜드마크 우선 모델과 운영체제 대체 경로
- [Depth Anything V2 Small](posture-analysis/depth-anything-v2.md) — 상대 깊이 모델과 제품 사용 범위

구현과 문서가 다르면 코드를 확인한 뒤 문서를 함께 갱신한다.
