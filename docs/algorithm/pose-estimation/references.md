# 상체 중심 자세 추정 — 참고 자료

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 공식 자료·1차 연구 목록 |
| 적용 상태 | 근거 문서 |
| 다루는 범위 | Apple Vision, 대안 pose 모델, CVA, 단안 3D pose, FHP 인접 연구 |
| 제품 내 역할 | [analysis.md](analysis.md)의 주장과 한계를 추적할 출처 제공 |

## 핵심 근거

| 주장 | 근거 수준 | 대표 출처 |
|---|---|---|
| Vision 2D는 상체 landmark와 관절별 confidence를 제공 | 공식 문서 | Apple Vision 문서·WWDC20 |
| 대안 pose 모델은 landmark 수·런타임·라이선스 조건이 다름 | 공식 모델 자료 | MediaPipe, MoveNet, OpenPose, HRNet 자료 |
| 사진 CVA와 앱 내부 자세 점수는 동일한 측정값이 아님 | 1차 연구·문헌 검토 | CVA 문헌, 방사선 비교 연구 |
| 단일 RGB 3D pose 기반 FHP 분류 선례가 있으나 목표 환경의 직접 성능은 아님 | 동료심사 연구 | JMIR Formative 2024 |

## 공식 문서와 1차 자료

- Apple Developer Documentation, `VNDetectHumanBodyPoseRequest`: <https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest>
- Apple Developer, WWDC20 “Detect Body and Hand Pose with Vision”: <https://developer.apple.com/videos/play/wwdc2020/10653/>
- Apple Developer, WWDC23 “Explore 3D body pose and person segmentation in Vision”: <https://developer.apple.com/videos/play/wwdc2023/111241/>
- Apple Developer, WWDC21 “Detect people, faces, and poses using Vision”: <https://developer.apple.com/videos/play/wwdc2021/10040/>
- Google AI Edge, MediaPipe Pose Landmarker guide: <https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker>
- Google AI Edge, MediaPipe Tasks Vision Swift API: <https://ai.google.dev/edge/api/mediapipe/swift/vision/Protocols>
- Google AI Edge, MediaPipe Tasks iOS setup: <https://ai.google.dev/edge/mediapipe/solutions/setup_ios>
- Bazarevsky et al., “BlazePose: On-device Real-time Body Pose tracking”: <https://arxiv.org/abs/2006.10204>
- TensorFlow Hub, “MoveNet: Ultra fast and accurate pose detection model”: <https://www.tensorflow.org/hub/tutorials/movenet>
- Cao et al., “OpenPose: Realtime Multi-Person 2D Pose Estimation using Part Affinity Fields”: <https://arxiv.org/abs/1812.08008>
- Sun et al., “Deep High-Resolution Representation Learning for Human Pose Estimation”: <https://arxiv.org/abs/1902.09212>
- Singla et al., “Photogrammetric Assessment of Upper Body Posture Using Postural Angles: A Literature Review”: <https://pubmed.ncbi.nlm.nih.gov/28559753/>
- Lee et al., “Recognition of Forward Head Posture Through 3D Human Pose Estimation With a Graph Convolutional Network”: <https://formative.jmir.org/2024/1/e55476>
- A Computer Vision-Based Application for the Assessment of Head Posture: <https://www.mdpi.com/2076-3417/13/6/3910>
- Modelling Proper and Improper Sitting Posture of Computer Users Using Machine Vision: <https://www.mdpi.com/2076-3417/13/9/5402>

## 추가·관련 자료

- MediaPipe Pose Landmarker guide (33 3D landmarks, GHUM): <https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker>
- 사진 CVA와 방사선 정렬 비교(R²≈0.30, 한계 근거): <https://pmc.ncbi.nlm.nih.gov/articles/PMC11012400/>
- CVA 정의 및 FHP 임계 논의 (tragus–C7, <50–53°): <https://pmc.ncbi.nlm.nih.gov/articles/PMC7559098/>
- 정면 평면 sternum-tragi 각 ↔ 3D CVA 상관 (frontal proxy 한계): <https://journals.sagepub.com/doi/abs/10.3233/WOR-213451>
- 단안 3D pose의 깊이 모호성(ill-posed) 서베이: <https://pmc.ncbi.nlm.nih.gov/articles/PMC12031093/>, <https://arxiv.org/html/2411.13026v1>
- 1€ filter (속도적응 스무딩): <https://gery.casiez.net/1euro/>

## 직접 적용하지 않는 범위

- 외부 모델의 mAP·FPS를 데이터셋과 하드웨어가 다른 상태에서 직접 비교하지 않는다.
- 사진 CVA 임계나 인접 연구의 정확도를 정면 Mac 웹캠 자세 판정 성능으로 전용하지 않는다.
- 3D landmark 또는 world coordinates를 실제 센서 depth나 임상 측정값으로 해석하지 않는다.
