# 관련 API — Face observation과 person instance mask

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | Vision 보조 사람 분석 API 리서치 |
| 적용 상태 | 현재 자세 판정 경로에 미채택 |
| 다루는 범위 | face bounding box·회전 값, 사람별 2D instance mask |
| 제품 내 역할 | body pose·depth와 혼동하지 않기 위한 경계 기록 |

## 핵심 근거

| API | 제공 정보 | 제공하지 않는 정보 | 현재 상태 |
|---|---|---|---|
| `VNFaceObservation` | face bounding box, 계산 가능한 yaw·roll·pitch | 몸통 관절, 실제 전방 거리, 자세 상태 | 미채택 |
| `VNGeneratePersonInstanceMaskRequest` | 사람별 전체 2D mask | 신체 부위 구분, z축 depth, 관절 | 미채택 |

## Face observation

face observation은 얼굴 bounding box와 요청 revision에서 계산 가능한 yaw·roll·pitch를 제공할 수 있다. 특정 angle이 계산되지 않으면 값은 `nil`일 수 있다.

회전 가드나 head ROI 보조 후보가 될 수 있지만 다음 이유로 현재 확정 흐름에는 넣지 않는다.

- face box 크기와 위치는 카메라 거리·높이·crop에 민감하다.
- 얼굴 회전 값은 머리의 실제 전방 이동 거리나 임상 CVA가 아니다.
- 현재 머리 ROI는 PoseNet 우선·Vision 2D fallback의 nose·eyes·ears로 정의할 수 있다.

## Person instance mask

`VNGeneratePersonInstanceMaskRequest`는 이미지에서 사람별 전체 mask를 만든다. Apple의 WWDC23 설명에는 최대 네 사람의 instance mask와 혼잡 장면에서의 누락·병합 가능성이 포함된다.

mask는 foreground/background 또는 사람 instance의 2D 픽셀 영역이다. 머리·목·몸통을 나누는 신체 부위 segmentation도 아니고, 픽셀별 깊이도 아니다. 따라서 mask만으로 머리와 몸통의 상대 전후 관계를 만들 수 없다.

## 현재 방식과의 관계

- PoseNet·Vision 2D: 머리·어깨 landmark와 ROI 품질
- Depth Anything V2: ROI의 relative depth
- 프로젝트 자세 분석기: baseline·품질·시간 조건을 적용한 상태 판정

face와 person mask는 이 최소 경로의 실패 원인과 추가 이득을 제품 데이터로 입증한 뒤에만 별도 변경으로 검토한다. 현재는 필수 입력, fallback 또는 신호 융합에 사용하지 않는다.

## 참고 자료

- Apple `VNFaceObservation`: <https://developer.apple.com/documentation/vision/vnfaceobservation>
- Apple `VNGeneratePersonInstanceMaskRequest`: <https://developer.apple.com/documentation/vision/vngeneratepersoninstancemaskrequest>
- WWDC23 “Explore 3D body pose and person segmentation in Vision”: <https://developer.apple.com/videos/play/wwdc2023/111241/>
