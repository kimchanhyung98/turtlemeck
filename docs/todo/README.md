# TODO — Local LLM / AI CLI 적용 계획

이 디렉토리는 기존 리서치 결과를 **보존**한 채, `turtlemeck`에 로컬 LLM과 AI CLI를 어떻게 적용할지 정리하는 실행 계획 공간이다. 기존 리서치 문서의 결론을 바꾸거나 덮어쓰지 않는다.

## 문서

| 문서 | 내용 |
|---|---|
| [local-llm-ai-cli-plan.md](local-llm-ai-cli-plan.md) | 로컬 LLM·Codex·Claude Code·Hugging Face 의존성·임시 이미지 분석 파이프라인 적용 계획 |
| [viewpoint-auto-workflow.md](viewpoint-auto-workflow.md) | 실행 중 시점 인식·히스테리시스·자동 분석 방식 라우팅 설계 |

## 우선 원칙

1. **자세 판정 런타임은 기존 리서치를 따른다.** 단일 RGB/AI depth는 절대 cm 측정기가 아니며, 제품 로직은 Apple Vision/Core ML 기반의 baseline 상대 신호를 우선한다.
2. **AI CLI는 앱 런타임이 아니라 개발/검증 보조 도구로 둔다.** 이미지 설명, 실패 사례 분류, 리서치 검토, 로그 요약에 사용하되 사용자 웹캠 이미지를 기본적으로 클라우드 CLI에 보내지 않는다.
3. **모델·이미지 파일은 임시 디렉토리에서 다룬다.** 재현 가능한 샘플만 `Samples/`에 두고, 임시 다운로드/분석물은 `$TMPDIR` 또는 `/tmp` 아래 run 디렉토리로 격리한다.
4. **모호한 CLI 플래그는 로컬 help와 공식 문서로 확인한다.** 현재 로컬 확인 기준 `codex -p`는 prompt가 아니라 profile 옵션이며, 비대화형 실행은 `codex exec`를 사용한다.
5. **제품 UI는 자동 시점 라우팅을 기본으로 한다.** 내부 회귀 테스트용 기하 방식과 ML 방식 수동 선택은 남기되, 수동 picker는 디버그 모드 전용으로 제한한다.

## 현재 로컬 확인

- `codex` 설치됨: `codex-cli 0.142.0`.
- `claude` 설치됨: Claude Code `2.1.191`.
- `ollama` 설치됨.
- `hf`/`huggingface-cli`는 현재 PATH에서 확인되지 않음.
- `scripts/run-tests.sh` 통과: `97 tests`.
- `swift test --disable-sandbox list`는 빌드 완료 후 SwiftPM 테스트 타깃 없음으로 종료. 이 프로젝트의 검증 경로는 `scripts/run-tests.sh`다.
- 현재 코드 구조 확인: 내부적으로 `PostureAlgorithmFactory`가 분석 방식을 선택하고, 공통 `PosturePipeline`이 시점 안정화·1€ 스무딩·재판정을 수행한다.
- 구현 진행 상태: 기본값을 `AI/ML 자동`으로 변경했고, 일반 UI는 자동 시점 라우팅을 사용하며 수동 방식 picker는 디버그 모드에서만 노출한다. `Resources/DepthAnythingV2SmallF16.mlpackage` 모델을 포함했다.
- 패키징 확인: `scripts/package-app.sh` 통과. `.build/turtlemeck.app`, `.zip`, `.dmg` 생성 및 `x86_64 arm64` universal binary 확인.
