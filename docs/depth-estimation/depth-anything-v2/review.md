# 리뷰: Depth Anything V2 리서치 (docs/depth-estimation/depth-anything-v2/)

- 리뷰 일자: 2026-07-21
- 대상 문서: [README.md](README.md), [analysis.md](analysis.md), [references.md](references.md)
- 종합 판정: 수정 필요

## 요약

references.md의 13개 URL을 전부 접속해 확인한 결과 모두 유효했고, 모델 크기·라이선스·Apple Core ML 수치·metric 변형 등 구체 수치가 1차 출처와 정확히 일치하며 번들 모델·제품 코드와도 부합한다. 유일한 실질 문제는 analysis.md 4절 처리 순서가 landmark 제공자를 "Vision 2D"로만 서술해 규범 문서·그룹 README·코드의 PoseNet 우선·Vision fallback 구조와 충돌하는 점이다. 그 외에는 적용 상태 용어와 괄호 표현 수준의 경미한 문제만 있다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| 기본 모델 출력은 affine-invariant inverse depth, scale·shift-invariant loss로 학습 | 일치 | <https://arxiv.org/html/2406.09414v1> — "our models produce affine-invariant inverse depth", "scale- and shift-invariant loss" |
| teacher는 595K 합성 이미지로 학습, 약 62M 레이블 없는 실제 이미지에 pseudo depth를 생성해 student 학습 | 일치 | <https://arxiv.org/html/2406.09414v1>, <https://depth-anything-v2.github.io/> — "595K images", "62M images" |
| DPT decoder와 DINOv2 encoder(backbone) 사용 | 일치 | <https://arxiv.org/html/2406.09414v1> Section 7.1 — "we use DPT as our depth decoder, built on DINOv2 encoders" |
| NeurIPS 2024 accept | 일치 | <https://arxiv.org/abs/2406.09414> — "Accepted by NeurIPS 2024" |
| relative 모델 파라미터 Small 24.8M / Base 97.5M / Large 335.3M / Giant 1.3B, Giant는 Coming soon(미공개) | 일치 | <https://github.com/DepthAnything/Depth-Anything-V2> 모델 표 |
| 라이선스 Small=Apache-2.0, Base/Large/Giant=CC-BY-NC-4.0(비상업) | 일치 | <https://github.com/DepthAnything/Depth-Anything-V2> LICENSE 안내 문구 |
| metric 변형은 Hypersim(실내)·Virtual KITTI(실외) fine-tune, 예제 max_depth 20/80, meters 출력 | 일치 | <https://github.com/DepthAnything/Depth-Anything-V2/blob/main/metric_depth/README.md> — "HxW depth map in meters in numpy" |
| Apple 모델 카드 값: 24.8M params, 49.8MB, M1 Max 32.80ms, M3 Max 24.58ms, Neural Engine, apache-2.0 | 일치 | <https://huggingface.co/apple/coreml-depth-anything-v2-small> 벤치마크 표 |
| Apple 공식 Core ML 변환은 Small만 존재, Large Core ML은 커뮤니티(LloydAI) 변환으로 cc-by-nc-4.0 승계 | 일치 | <https://huggingface.co/apple>, <https://huggingface.co/LloydAI/DepthAnything_v2-Large-CoreML> — "As a derivative work ... also under cc-by-nc-4.0" |
| 번들 모델이 Apple 배포본과 일치 (이름·Apache 2·입력 짧은 변 518px·14의 배수·release 2024-06) | 일치 | `Resources/DepthAnythingV2SmallF16.mlpackage` model.mlmodel 메타데이터, weight.bin 49,419,072 bytes |
| 현재 제품은 Small만 사용 | 일치 | `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift:16` (modelName 기본값 "DepthAnythingV2SmallF16"), Resources에 해당 mlpackage만 존재 |
| 4절 feature 통계(머리·몸통 ROI median, reference ROI IQR 정규화, 방향 통일)가 코드와 일치 | 일치 | `Sources/TurtleCore/Detection/PostureAnalyzer.swift:99-119` — feature = direction.multiplier * (head - torso) / referenceIQR |
| README.md의 PoseNet 우선·Vision 2D fallback 서술이 코드와 일치 | 일치 | `Sources/TurtleCore/Camera/PoseDetector.swift:17-21` — poseNet.detect 먼저 시도 후 Vision fallback |
| Video Depth Anything은 단일 이미지 depth 모델의 temporal flicker를 다루는 CVPR 2025(Highlight) 논문 | 일치 | <https://arxiv.org/abs/2501.12375>, CVPR 2025 open access |
| 추가 자료 4건(Zero-shot Depth Completion, StableDPT, InSpaceType, PLOS Comput Biol 2025) 실재·내용 일치 | 일치 | <https://arxiv.org/html/2502.06338v1>, <https://arxiv.org/abs/2601.02793>, <https://arxiv.org/abs/2408.13708>, <https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1013020> |

## 발견된 문제

### 수정 필요 (major)

- **analysis.md — 4절 처리 순서의 landmark 제공자 서술이 규범과 충돌**
  - 문서 서술: 4절 1단계 "Vision 2D가 머리·목·어깨 landmark와 confidence를 제공한다." (analysis.md:65)
  - 문제: 규범 문서 [posture-analysis-workflow.md](../../algorithm/posture-analysis-workflow.md)는 2026-07-21 결정에 따라 2D landmark 역할을 PoseNet 우선·Vision fallback으로 정의하고(3행, 4절), 같은 그룹의 README.md:14도 "PoseNet 우선·Vision 2D fallback이 신체 관절·ROI를 제공"이라고 쓰며, 코드도 PoseNet을 먼저 시도한다. analysis.md만 landmark 제공자를 Vision 2D 단독으로 서술해 그룹 내부·규범·코드 세 곳과 불일치한다. analysis.md가 workflow 문서를 "확정 플로우"로 직접 링크하는 점에서 개략 서술로 볼 수도 없다.
  - 근거: docs/algorithm/posture-analysis-workflow.md:3, 4절, docs/depth-estimation/depth-anything-v2/README.md:14, Sources/TurtleCore/Camera/PoseDetector.swift:17-21

### 권장 (minor)

- **README.md·analysis.md — 정의되지 않은 적용 상태 용어 "제품 실측 필요"**
  - 문서 서술: README.md:8 "DA-V2 Small 채택, 국소 자세 신호는 제품 실측 필요", analysis.md:8 "자세 feature는 제품 실측 필요"
  - 문제: 문서 규칙의 적용 상태 용어 표(docs/algorithm/README.md — 채택/보조/검증 필요/미채택/제외/근거 문서)에 없는 표현이다. 같은 의미의 정의 용어는 "검증 필요"이며, 동일 신호를 다루는 etc/related-feature-design.md:8은 "검증 필요"를 쓰고 있어 용어가 갈린다.
- **references.md — 출처에 없는 "(i.i.d. 가정)" 프레임**
  - 문서 서술: references.md:34 "단일 이미지 depth의 temporal flicker (i.i.d. 가정) — Video Depth Anything"
  - 문제: 논문은 단일 이미지 모델이 "designed for static images ... suffer from flickering"이라고 설명할 뿐 "i.i.d. 가정"이라는 용어나 독립성 가정 프레임을 사용하지 않는다. temporal flicker 요약 자체는 정확하므로 괄호 표현만 출처 기반으로 완화하면 된다.

## 참고 (info)

- **analysis.md:59 — "PyTorch F32 출력과 Core ML 출력의 일치도"**: Apple 모델 카드는 F16 변환본의 abs-rel error(0.0089)를 "small-original" PyTorch 모델 기준으로 보고하지만, 기준 모델의 정밀도가 F32라는 표기는 카드에서 직접 확인하지 못했다. 실질 오류로 보기는 어려워 참고로만 기록한다.

## 결론

세 문서의 외부 사실(논문·저장소·모델 카드 수치, 라이선스, URL 13건)과 내부 사실(번들 모델, 제품 코드)은 전부 1차 출처와 일치해 사실 정확도는 매우 높다. 다만 analysis.md 4절의 landmark 제공자 서술이 2026-07-21 확정된 PoseNet 우선·Vision fallback 구조와 충돌하므로 해당 문장을 규범 문서·README와 같은 표현으로 수정해야 한다. 적용 상태 용어 통일과 references.md의 괄호 표현 완화는 권장 사항이다.
