# 리뷰: metric depth 모델 리서치 (docs/depth-estimation/metric-depth-models/)

- 리뷰 일자: 2026-07-21
- 대상 문서:
  - [README.md](README.md)
  - [analysis.md](analysis.md)
  - [references.md](references.md)
- 종합 판정: 경미한 수정 권장

## 요약

세 문서의 외부 사실 주장(ZoeDepth 보관·MIT, Metric3D BSD-2-Clause·canonical camera space·focal length 경로, UniDepth CC BY-NC 4.0·intrinsic 동시 추정·scale 한계)은 공식 저장소와 논문으로 전부 확인됐고, references.md의 외부 URL 7개와 내부 링크 3건도 모두 유효하다. 미채택 판단은 규범 문서와 depth-estimation 인덱스의 상태 표와 일치하며, 현재 코드 서술도 실제 구현과 일치한다. 발견된 문제는 README.md가 공통 README 형식 중 두 섹션을 누락한 형식 위반(minor) 하나로, 사실 정확도에는 문제가 없다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| ZoeDepth 공식 저장소는 2025년 5월 보관 상태이며 MIT 라이선스 (analysis.md §1, references.md) | 일치 | <https://github.com/isl-org/ZoeDepth> — 2025-05-05 archived, Intel 유지보수 종료 고지, MIT License |
| ZoeDepth는 relative backbone(MiDaS)과 metric bins module 결합, 추론 시 intrinsic 불요 (analysis.md §1) | 일치 | <https://arxiv.org/abs/2302.12288> ("metric bins module"), 저장소의 intrinsic 없는 추론 예시 |
| Metric3D 공식 저장소는 BSD-2-Clause (analysis.md §1, references.md) | 일치 | <https://github.com/YvanYin/Metric3D> — "The Metric 3D code is under a 2-clause BSD License" |
| Metric3D v2는 canonical camera space로 카메라별 ambiguity를 해결하고 scale 복원에 focal length가 중요 (README.md, analysis.md §1) | 일치 | <https://arxiv.org/abs/2404.15506> (canonical camera space transformation module), 저장소 README의 canonical_space focal_length=1000.0·focal 오설정 시 point cloud 왜곡 설명 |
| Metric3D는 intrinsic이 없을 때 기본 focal length 설정 경로 제공 (analysis.md §1) | 일치 | 저장소 in-the-wild 모드 "by default 9 settings of focal length" |
| UniDepth는 camera module로 intrinsic을 함께 추정, 추론 시 별도 intrinsic 불요 (README.md, analysis.md §1) | 일치 | <https://arxiv.org/abs/2403.18913> abstract, 저장소의 RGB만으로 depth+intrinsics 예측(intrinsic은 선택 입력) |
| UniDepth 공식 저장소는 CC BY-NC 4.0 비상업 (analysis.md §1, references.md) | 일치 | <https://github.com/lpiccinelli-eth/UniDepth> — LICENSE: Creative Commons BY-NC 4.0 |
| UniDepth 논문은 특정 장면 scale 포착 실패를 한계로 명시 (analysis.md §1) | 일치 | <https://ar5iv.labs.arxiv.org/html/2403.18913> §4.2 ("fail to capture the specific scene scales", ETH3D·IBims-1) |
| UniDepth V2 논문 링크 (references.md) | 유효 | <https://arxiv.org/abs/2502.20110> — "UniDepthV2: Universal Monocular Metric Depth Estimation Made Simpler" |
| "PoseNet 우선·Vision 2D fallback" (analysis.md §3) | 코드와 일치 | `Sources/TurtleCore/Camera/PoseDetector.swift:17-21` — poseNet.detect 결과가 유효 상체를 못 만들 때만 Vision 요청 수행 |
| "Apple 배포 Core ML DA-V2 Small로 relative depth 생성" (analysis.md §3) | 코드·번들·배포처와 일치 | `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift:16` (`DepthAnythingV2SmallF16`), `Resources/DepthAnythingV2SmallF16.mlpackage`, <https://huggingface.co/apple/coreml-depth-anything-v2-small> |
| "metric 모델·ONNX 런타임·카메라 calibration을 추가하지 않는다" (analysis.md §3) | 코드베이스와 일치 | Sources/·Makefile·package.sh에 onnx 참조 0건, `Sources/TurtleCore/Camera/` 아래 calibration 코드 없음 |
| 미채택 판단이 규범 문서·인덱스와 일치 (README.md, analysis.md §3) | 일치 | `docs/algorithm/posture-analysis-workflow.md` §13 (Depth Pro·metric depth·video depth 모델 미사용), `docs/depth-estimation/README.md` 기술별 적용 상태 표 |
| references.md 내부 링크 3건 | 모두 실제 파일로 연결 | `docs/depth-estimation/depth-anything-v2/README.md`, `docs/depth-estimation/apple-depth-pro/README.md`, `docs/algorithm/posture-analysis-workflow.md` 존재 확인 |

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

- **README.md — 공통 README 형식 섹션 누락**
  - 문서 서술: README 구성이 문서 요약 → 제품 적용 판단 → 핵심 차이 → 문서 구성.
  - 문제: `docs/algorithm/README.md`의 공통 README 형식(1. 문서 요약 표, 2. 요약 플로우, 3. 제품 적용 판단, 4. 한계와 검증 상태, 5. 문서 구성) 중 "요약 플로우"와 "한계와 검증 상태" 섹션이 없다. metric-depth-models는 인덱스가 예외로 명시한 `etc/`에 해당하지 않는 독립 방식 디렉토리이므로 형식 대상이다. 채택 문서인 `depth-anything-v2/README.md`는 요약 다이어그램과 "한계와 검증 상태"를 포함한 다섯 섹션을 모두 갖추고 있어 그룹 간 형식이 어긋난다. "핵심 차이" 표가 한계 일부를 다루지만 검증 상태 정리는 없다.
  - 근거: `docs/algorithm/README.md:51-57` (README 형식 정의), `docs/algorithm/README.md:37` (예외는 상위 README 문서 구성 표에 명시), `docs/depth-estimation/README.md:49` (`etc/`만 예외로 명시), `docs/depth-estimation/depth-anything-v2/README.md` 헤더 구성.

## 참고 (info)

- **analysis.md §1 — UniDepth camera diversity 서술의 출처 문맥**
  - 문서 서술: "저자들은 특정 장면 scale을 포착하지 못하는 사례와 제한된 camera diversity를 한계로 설명한다."
  - 참고: 전반부(scale 포착 실패)는 논문 한계 절(§4.2)에서 확인되지만, "제한된 camera diversity"는 한계 절이 아니라 방법 절(§3.4)에서 camera module 학습 난점("the low variety of effective cameras compared to the image diversity")으로 서술된 내용이다. 두 가지를 모두 "한계로 설명한다"고 묶은 표현은 출처 문맥보다 약간 확대된 요약이다. 실질 내용 자체는 논문에 존재한다.
  - 근거: <https://ar5iv.labs.arxiv.org/html/2403.18913> §4.2, §3.4.

## 결론

외부 사실·라이선스·링크·코드 일치 여부 모두에서 오류가 발견되지 않은, 정확도가 높은 문서 그룹이다. README.md에 "요약 플로우"와 "한계와 검증 상태" 섹션을 보충해 공통 README 형식을 맞추는 경미한 수정만 권장한다.
