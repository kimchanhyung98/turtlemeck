# 리뷰: depth 교차 연구 (docs/depth-estimation/etc/)

- 리뷰 일자: 2026-07-21
- 대상 문서:
  - [related-feature-design.md](related-feature-design.md)
  - [related-posture-feasibility.md](related-posture-feasibility.md)
  - [related-temporal-video-depth.md](related-temporal-video-depth.md)
- 종합 판정: 경미한 수정 권장

## 요약

세 문서는 전반적으로 정확하고 절제된 문서다. 외부 사실 주장(δ1 정의, PreventFHP 초록 범위, JMIR 78%·BMC 82.4% 정확도, Video Depth Anything의 존재와 relative depth 출력)은 모두 원출처와 일치했고, feature 후보 식·품질 조건·버스트 집계는 PostureAnalyzer/BurstProcessor 구현 및 규범 문서와 정합한다. 발견된 문제는 접근이 제한된 참고 URL 3건과 프레임 제외·버스트 `noEval` 구분을 뭉뚱그린 표현 1건뿐으로, 실질적 사실 오류나 규범 충돌은 없었다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| Video Depth Anything 논문이 실재하며 단일 이미지 depth의 temporal inconsistency를 직접 다루고 긴 영상의 일관된 depth를 목표로 한다 (related-temporal-video-depth.md) | 일치 | <https://arxiv.org/abs/2501.12375> — "Consistent Depth Estimation for Super-Long Videos", DA-V2 확장 + temporal consistency loss |
| Video Depth Anything 기본 출력도 affine-invariant이므로 video 모델로 절대 측정 문제가 해결되지 않는다 | 일치 — 기본 추론은 relative depth, metric은 별도 변형(2025-08 릴리스) | <https://github.com/DepthAnything/Video-Depth-Anything> (CVPR 2025 highlight) |
| Depth Anything V2 논문이 실재하며 metric 변형은 별도 fine-tune 모델이다 | 일치 | <https://arxiv.org/abs/2406.09414> 초록 — "we fine-tune them with metric depth labels to obtain our metric depth models" |
| δ1은 예측 depth와 ground truth의 비율 오차가 1.25 이내인 픽셀 비율이다 (related-posture-feasibility.md 1절) | 표준 정의와 일치 | 단안 depth 서베이 <https://arxiv.org/pdf/2406.19675> 등 — δ_th = (1/N) Σ [max(d/d̂, d̂/d) < 1.25] |
| PreventFHP는 공개 초록 기준 상용 depth 카메라 사례이며 Kinect 기기명은 초록에 없다 (같은 문서 3절) | 일치 — 초록에 "inexpensive commercial depth camera"·98.0% 검출 정확도, Kinect 미언급 | <https://www.semanticscholar.org/paper/91c03f9ba524f42cc360685235b6b0ece30665b3> (IEEE 6775470, 2014 Haptics Symposium) |
| 단일 RGB→3D pose→GCN FHP 분류 연구는 약 78% 정확도이며 데이터·시점이 고정 정면 Mac 경로와 다르다 | 일치 — test accuracy 78.27%, macro F1 77.54%, StateFarm·YouTube 데이터 | <https://pmc.ncbi.nlm.nih.gov/articles/PMC11384178/> (JMIR Formative 2024 e55476) |
| 측면 landmark 기반 FHP 연구는 82.4% 정확도이며 표준화된 측면 촬영과 청소년 데이터에 기반한다 | 일치 — Extra Tree Classifier accuracy 82.4%, specificity 85.5%, 측면(sagittal) 프로토콜, 중국 10~15세 | <https://pmc.ncbi.nlm.nih.gov/articles/PMC10496156/> (BMC Med Inform Decis Mak, 10.1186/s12911-023-02285-2) |
| PMC9354067은 비방사선 FHP 측정 문헌고찰이다 | 일치 | <https://pmc.ncbi.nlm.nih.gov/articles/PMC9354067/> — "Reliability and Validity of Non-radiographic Methods of Forward Head Posture Measurement: A Systematic Review" |
| Apple Vision 2D body pose 문서 링크가 유효하다 | 일치 — 페이지 title 확인 | <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images> |
| 후보 식 `feature = direction * (head - torso) / scale` (head·torso는 ROI median, scale은 landmark 기반 reference ROI의 IQR)이 구현과 같다 (related-feature-design.md) | 일치 | `Sources/TurtleCore/Detection/PostureAnalyzer.swift:99-101` (median·IQR), `:119` (feature 식), `:159-164` (reference ROI) |
| `scale`이 최소 품질 조건을 충족할 때만 feature를 계산한다 | 일치 | `PostureAnalyzer.swift:101-102` (`referenceIQR >= Tuning.minimumReferenceIQR` 게이트, 실패 시 `insufficientDepthRange`), `Tuning.swift:15` |
| 현재 결정(버스트 프레임별 처리, feature median 대표값, MAD 기반 불안정 `noEval`, 지속된 `bad`만 상태 전이)이 구현과 같다 (related-temporal-video-depth.md) | 일치 | `Sources/TurtleCore/Detection/BurstProcessor.swift:24-25` (median·MAD), `:53-54` (MAD 초과 → `noEval` "unstable burst"), `Tuning.swift:19,24` (`maximumBurstMAD`, `requiredBadBursts = 2`) |
| 품질 조건 목록(landmark confidence, ROI 최소 유효 픽셀, 화면 경계 접촉 제한, 경계 픽셀 제외)이 코드 검사 항목과 대응한다 | 일치 | `PostureAnalyzer.swift:12-19` (reliable landmark), `:41-58` (boundaryContactRatio), `:75-82` (minimumROIPixels·minimumValidDepthRatio), `:151-164` (roiErosionFraction inset) |
| 전역 affine 변환 `d' = a·d + b` (`a > 0`)에서 feature가 보존되며 전역 scale·shift만 제거한다 | 수학적으로 타당 — median·IQR 모두 a>0 affine에 equivariant이므로 (head'-torso')/IQR' = a(head-torso)/(a·IQR)로 보존, 국소 왜곡 미제거 한계 서술도 정확 | 수식 검증 + [../depth-anything-v2/analysis.md](../depth-anything-v2/analysis.md) 68·72행 |
| 세 문서의 적용 상태(검증 필요 / 근거 문서 / 미채택)와 `etc/` 예외 규칙이 상위 문서와 정합한다 | 일치 | [../README.md](../README.md) 45-49행 (적용 상태 표·예외 디렉토리 명시), [../../algorithm/README.md](../../algorithm/README.md) 84-93행 (상태 용어) |

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

1. related-posture-feasibility.md — 참고 자료의 접근 제한 URL
   - 문서 서술: PreventFHP <https://ieeexplore.ieee.org/document/6775470/>, 단일 RGB→3D pose→GCN <https://formative.jmir.org/2024/1/e55476>, 측면 landmark <https://link.springer.com/article/10.1186/s12911-023-02285-2>
   - 문제: 세 URL 모두 자동화된 본문 접근에 실패했다(IEEE·JMIR은 빈 콘텐츠, Springer는 로그인 redirect 루프). 링크 자체는 유효하고 인용 내용도 정확하므로 봇 차단성 접근 제한으로 보인다.
   - 근거: 대체 소스로 내용 확인 — <https://pmc.ncbi.nlm.nih.gov/articles/PMC11384178/>, <https://pmc.ncbi.nlm.nih.gov/articles/PMC10496156/>, <https://www.semanticscholar.org/paper/91c03f9ba524f42cc360685235b6b0ece30665b3>. 안정적으로 접근 가능한 PMC/PubMed 미러 URL 병기를 고려할 만하다.
2. related-feature-design.md — 품질 조건의 프레임/버스트 수준 미구분
   - 문서 서술: "다음 중 하나라도 만족하지 못하면 `noEval`이다." 뒤에 프레임 단위 조건(필수 landmark confidence, ROI 최소 유효 픽셀 등)과 버스트 단위 조건(버스트 내 feature 분산)을 하나의 목록으로 나열
   - 문제: 규범 문서와 코드에서 landmark confidence·ROI 픽셀 부족 등 프레임 단위 실패는 "프레임 제외"이고, 유효 프레임이 충분히 남으면 버스트는 계속 평가된다. `noEval`은 유효 프레임 부족·분산 과다 등 버스트 단위 조건에서만 확정된다. 프레임/버스트 수준을 구분해 서술하면 정확해진다.
   - 근거: `PostureAnalyzer.swift:9-96` (프레임 실패는 exclusionReason으로 기록되어 프레임 제외), `BurstProcessor.swift:41-63` (`noEval`은 버스트 수준 조건에서만 반환), [../../algorithm/posture-analysis-workflow.md](../../algorithm/posture-analysis-workflow.md) 3장 표(필수 landmark 실패 → "프레임 제외") 및 149행 "일부 프레임이 제외되어도 버스트에 충분한 유효 프레임이 남으면 분석을 계속한다"

## 참고 (info)

없음.

## 결론

세 문서 모두 외부 인용과 코드·규범 문서 정합성에서 사실 오류가 발견되지 않았다. 절대 측정 주장을 제한하고 인접 연구의 적용 범위를 명시하는 서술 방식도 원출처와 일치한다. related-feature-design.md의 품질 조건 표현을 프레임/버스트 수준으로 구분하고, related-posture-feasibility.md 참고 자료에 접근 안정적인 미러 URL을 병기하는 경미한 수정만 권장한다.
