# 리뷰: 상체 자세 추정 로직·기하·baseline 리서치 (docs/algorithm/pose-estimation/)

- 리뷰 일자: 2026-07-21
- 대상 문서:
  - [README.md](README.md)
  - [analysis.md](analysis.md)
  - [comparison.md](comparison.md)
  - [references.md](references.md)
  - [related-baseline-calibration.md](related-baseline-calibration.md)
  - [related-cva-metrics.md](related-cva-metrics.md)
  - [related-monocular-limits.md](related-monocular-limits.md)
  - [related-viewpoint-geometry.md](related-viewpoint-geometry.md)
- 종합 판정: 수정 필요

## 요약

외부 사실 인용은 전반적으로 매우 정확하다. Apple PoseNet 샘플의 관절 수·라이선스, Vision 2D API 계약, 대안 모델 라이선스, CVA 문헌 수치(R²≈0.30, MD 4.84° 등)가 모두 원출처와 일치했고, 채택 경로·간격·통계 서술도 실제 코드와 부합한다. 다만 2026-07-21 PoseNet 우선 전환 이후 related-viewpoint-geometry.md가 갱신되지 않아 현재 채택 경로를 "Vision 2D 단독"으로 기술하며 규범 문서·코드와 충돌한다. 그 외에는 related-monocular-limits.md의 잔존 문구 1건과 references.md의 출처 표기 관련 소소한 이슈만 있다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| Vision `VNDetectHumanBodyPoseRequest`는 macOS 11+에서 최대 19개 body point와 point별 confidence 제공 (comparison.md, analysis.md) | 일치 | <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images> ("up to 19 unique body points"), WWDC20 10653 |
| Apple Core ML 샘플은 서드파티 PoseNet 모델을 번들하며 17개 관절 검출 (README.md, analysis.md, references.md) | 일치 | <https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image> ("PoseNet models detect 17 different body parts or joints"), 샘플 zip 내 `PoseNetMobileNet075S16FP16.mlmodel` |
| PoseNet 모델 Apache-2.0, 샘플 코드 MIT (comparison.md) | 일치 | 샘플 zip의 LICENSE.txt 원문, 로컬 `Resources/ThirdPartyNotices.md`와도 일치 |
| Vision 3D는 hip-rooted 17-joint skeleton이며 per-joint confidence 미문서화 (README.md, analysis.md의 제외 근거) | 일치 | WWDC23 111241 (17 joints, origin at root joint at center of hip), `VNHumanBodyPose3DObservation` 문서 |
| MediaPipe 33 landmark·macOS 미명시·Apache-2.0, MoveNet 17 keypoint·Apache-2.0, OpenPose 비상업 연구용, Ultralytics AGPL-3.0/Enterprise (comparison.md) | 모두 일치 | <https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker>, MoveNet SinglePose 모델 카드, OpenPose LICENSE, <https://www.ultralytics.com/license> |
| 사진 CVA vs 방사선: n=120, CVA vs C2-C7 SVA r=−0.549/R²=0.301, CVA vs ARA r=0.524/R²=0.275, "CVA는 방사선 경추 전만을 대체할 수 없다" (related-cva-metrics.md §3) | 수치·결론 정확히 일치 | <https://pmc.ncbi.nlm.nih.gov/articles/PMC11012400/> |
| FHP-목통증 메타분석: 성인 MD 4.84°(95% CI 0.14~9.54), 청소년 MD −1.05°(−4.23~2.12) 비유의 (related-cva-metrics.md §2) | 일치 | <https://pmc.ncbi.nlm.nih.gov/articles/PMC6942109/> |
| 중증 FHP 임계 <40°/<45°/<50° 비합의, 측정 프로토콜(tragus·C7 마커, 시상면 직교 촬영) (related-cva-metrics.md §1~2) | 일치 | <https://pmc.ncbi.nlm.nih.gov/articles/PMC11042887/> |
| JMIR Formative 2024 e55476: 단일 RGB→3D pose→GCN, shoulder angle 분포 중첩으로 단일 각 구분 곤란 (related-cva-metrics.md §2) | 일치 | <https://pmc.ncbi.nlm.nih.gov/articles/PMC11384178/> |
| 측면 landmark 기반 FHP 분류 82.4% 사례 (related-viewpoint-geometry.md) | 일치 | <https://pmc.ncbi.nlm.nih.gov/articles/PMC10496156/> (BMC Med Inform Decis Mak 2023, Extra Tree Classifier 82.4%) |
| DA-V2 기본 모델은 relative depth, metric은 별도 fine-tuning 변형 (analysis.md, related-monocular-limits.md) | 일치 | <https://arxiv.org/abs/2406.09414> |
| PoseNet 우선·Vision 2D fallback, 17개 PoseNet 관절, 공통 `PoseLandmarks` 계약, neck은 Vision에서만 (README.md, analysis.md, comparison.md) | 코드와 일치 | `Sources/TurtleCore/Camera/PoseDetector.swift:17-33`, `Sources/TurtleCore/Camera/PoseNetDetector.swift:125-143`, `Sources/TurtleCore/Detection/Models.swift:107-142` |
| 분석 간격 최소 20초(clamp 20~180초), 버스트 최대 5프레임, feature = direction × (head−torso)/reference IQR, baseline은 median+MAD·보정 3버스트 (analysis.md §3~4, related-baseline-calibration.md) | 코드와 일치 | `Sources/TurtleCore/Storage/Settings.swift:73-75`, `Sources/TurtleCore/Camera/CameraManager.swift:836`, `Sources/TurtleCore/Detection/PostureAnalyzer.swift:98-119`, `Sources/TurtleCore/Detection/Calibrator.swift:32-43`, `Sources/TurtleCore/Detection/Tuning.swift:22` |

## 발견된 문제

### 수정 필요 (major)

- **related-viewpoint-geometry.md — 현재 채택 경로를 Vision 2D 단독으로 기술**
  - 문서 서술: "이 복잡도는 Vision 2D + DA-V2 Small이라는 현재 경로의 유효성을 먼저 확인하는 데 방해가 된다"(28행), "고정된 정면 입력에서 Vision 2D는 머리·몸통 ROI와 품질을 제공하고, DA-V2 Small은 relative depth를 제공한다"(현재 적용 절, 32행).
  - 문제: 2026-07-21 PoseNet 우선 전환 이후 이 문서만 갱신이 누락됐다. 문서 전체에 PoseNet 언급이 없고 현재 적용 파이프라인 구성을 Vision 2D 단독 사실로 기술한다. 시점별 라우팅 미채택 논거가 아니라 "현재 적용" 서술이므로, 미채택 리서치 문서라는 이유로 면제되지 않는다.
  - 근거: 규범 문서 `docs/algorithm/posture-analysis-workflow.md:3` ("PoseNet 우선·Vision fallback으로 구현"), 같은 문서 153행 ("PoseNet을 우선 사용하고 유효한 상체를 만들 수 없을 때 Apple Vision 2D로 fallback"), 같은 그룹의 [README.md](README.md) 8·37행, [analysis.md](analysis.md), [comparison.md](comparison.md)는 모두 PoseNet 우선으로 갱신됨. 코드 `Sources/TurtleCore/Camera/PoseDetector.swift:17-22`도 PoseNet을 먼저 실행하고 실패 시에만 Vision으로 fallback한다.

### 권장 (minor)

- **related-monocular-limits.md — "현재 대응" 절의 잔존 문구**
  - 문서 서술: "Vision 2D confidence로 평가 가능한 프레임만 선택한다"(33행).
  - 문제: 확정 플로우에서 프레임 선택의 우선 입력은 PoseNet landmark confidence이고 Vision 2D는 fallback이다. 문장 취지는 fallback 경로에 한해 참이지만, PoseNet 전환 이전 서술이 남아 같은 그룹 문서·규범 문서와 어긋난다.
  - 근거: `docs/algorithm/posture-analysis-workflow.md:153`, `Sources/TurtleCore/Camera/PoseDetector.swift:17-22`.
- **references.md — 출처 유형 표기 부정확 1건**
  - 문서 서술: "단안 3D pose의 깊이 모호성(ill-posed) 서베이: PMC12031093, arXiv 2411.13026"(50행).
  - 문제: 두 번째 출처(arXiv 2411.13026, "X as Supervision: Contending with Depth Ambiguity in Unsupervised Monocular 3D Pose Estimation")는 서베이가 아니라 개별 방법 논문이다. depth ambiguity가 ill-posed라는 인용 내용 자체는 뒷받침되지만 "서베이" 표기는 첫 번째 출처(PMC12031093, Sensors 2025)에만 맞다.
  - 근거: <https://arxiv.org/html/2411.13026v1> (multi-hypothesis 방법 제안), <https://pmc.ncbi.nlm.nih.gov/articles/PMC12031093/> (실제 서베이).
- **references.md — 자동 접속이 실패하는 링크**
  - 대상: <https://www.mdpi.com/2076-3417/13/6/3910>, <https://www.mdpi.com/2076-3417/13/9/5402>, <https://formative.jmir.org/2024/1/e55476>.
  - 문제: 자동 검증에서 MDPI 2건은 HTTP 403(봇 차단), formative.jmir.org는 빈 본문으로 렌더링됐다. 세 문헌 모두 검색·PMC 미러(PMC11384178)로 실재와 제목 일치를 확인했으므로 실제 브라우저에서는 접근 가능할 가능성이 높다. 안정적 인용을 원하면 JMIR 건은 PMC 링크(PMC11384178) 병기를 고려할 수 있다.

## 참고 (info)

- references.md·comparison.md의 Google AI Edge 링크(`ai.google.dev/edge/mediapipe/...` 3건)는 `developers.google.com`으로 301 영구 리다이렉트된다. 도달은 되므로 깨진 링크는 아니지만, 영구 이전이므로 최신 URL로 갱신하면 더 안정적이다.
- references.md 49행의 "정면 평면 sternum-tragi 각 ↔ 3D CVA 상관 (frontal proxy 한계)" 표기: 해당 논문(WOR-213451)은 moderate 상관을 근거로 "정면 각으로 시상면 CVA 변화를 예측할 수 있다"는 긍정적 결론을 내린다. "한계"라는 표기는 문서의 해석(moderate 수준이라 개인 판정 proxy로는 부족)으로는 성립하지만 출처 자체의 논조와 방향이 달라 오해 소지가 있다. 근거 사용 맥락을 한 줄 보충하면 명확해진다.

## 결론

모델 스펙·라이선스·임상 수치·API 계약 인용의 정확도는 높고, 코드와의 정합성도 확인됐다. 수정이 필요한 항목은 related-viewpoint-geometry.md의 "현재 경로/현재 적용" 서술을 PoseNet 우선·Vision 2D fallback으로 갱신하는 것 하나이며, related-monocular-limits.md의 잔존 문구와 references.md의 서베이 표기·링크 병기는 함께 정리하면 좋다. 이 갱신 외에는 문서 그룹의 결론과 근거 구조를 바꿀 이유가 없다.
