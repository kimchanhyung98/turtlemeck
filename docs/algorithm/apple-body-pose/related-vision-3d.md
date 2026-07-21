# 관련 API — Apple Vision 3D body pose

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | Apple Vision 3D API 리서치 |
| 적용 상태 | 현재 자세 판정 경로에서 제외 |
| 입력 | RGB 이미지, 선택적인 호환 depth metadata |
| 출력 | 가장 두드러진 사람의 17-joint 3D skeleton |
| 제품 내 역할 | 2D pose·단안 relative depth와 혼동하지 않기 위한 제외 근거 |

## 1. API 계약

`VNDetectHumanBodyPose3DRequest`는 iOS 17와 macOS 14부터 제공된다. 초기 revision은 프레임에서 가장 두드러진 한 사람의 17개 관절을 추정한다. Apple은 필요한 관절 일부만 반환하는 방식이 아니라 17개 전체를 얻거나 observation을 얻지 못하는 계약으로 설명한다.

관절은 top/center head, center shoulder, spine, root, 양쪽 shoulder/elbow/wrist, 양쪽 hip/knee/ankle로 구성된다. 2D body pose의 19개 point와 관절 집합이 같지 않다.

## 2. 좌표 표현

| 표현 | 기준 |
|---|---|
| `position` | skeleton root인 hip 중심 기준 model-space 위치 |
| `localPosition` | 해당 관절의 parent joint 기준 위치 |
| `cameraOriginMatrix` | camera와 skeleton root 사이의 변환 |
| `pointInImage(_:)` | 3D joint를 입력 이미지의 2D 점으로 투영 |

3D 위치 단위는 meter로 표현되지만, 이 사실만으로 RGB 단안 입력의 실제 거리나 신체 치수가 측정됐다고 볼 수 없다. 좌표의 기준과 scale 산출 방식을 함께 확인해야 한다.

## 3. depth metadata와 신장 추정

- RGB 이미지만으로도 요청할 수 있다.
- Portrait/AVFoundation의 호환 depth data와 camera calibration이 있으면 scale과 깊이 정확도에 도움을 준다.
- `bodyHeight`는 `heightEstimation`이 measured일 때 측정 기반 값이다.
- 호환 depth가 없으면 Apple이 설명한 reference height 1.8m를 사용한 추정 scale일 수 있다.
- `cameraOriginMatrix`, `bodyHeight`, `heightEstimation`은 관절별 confidence가 아니다.

목표 Mac 내장 RGB 카메라 경로는 호환 measured depth를 전제로 하지 않는다. 따라서 meter 단위 출력만 보고 머리가 몸통보다 실제로 몇 cm 전방에 있다고 해석하지 않는다.

## 4. confidence

`VNHumanBodyRecognizedPoint3D`에는 Vision 2D recognized point와 같은 per-joint confidence가 없다. observation은 `VNObservation` 계층의 observation-level confidence를 제공하지만, 이 값 하나로 17개 관절 각각의 품질을 보장할 수 없다.

`bodyHeight`, `heightEstimation`, `cameraOriginMatrix`를 누락된 per-joint confidence의 대체값으로 사용하지 않는다.

## 5. 현재 제품에서 제외하는 이유

- 출력은 sparse 17-joint skeleton이며 머리·몸통의 dense depth map이 아니다.
- 목표 카메라 입력에는 measured scale을 보강할 호환 depth가 없다.
- 관절별 confidence가 없어 머리·몸통 전후 feature의 품질 게이트와 맞지 않는다.
- 현재 확정 흐름은 PoseNet 우선·Vision 2D fallback으로 2D ROI를 만들고 Depth Anything V2 relative depth를 baseline과 비교한다.

따라서 Vision 3D의 joint position, body height, camera transform을 feature·baseline·fallback에 넣지 않는다. 이는 API가 macOS에서 실행 불가능하다는 뜻이 아니라 현재 제품이 요구하는 관측값과 품질 계약에 맞지 않는다는 뜻이다.

## 6. Vision 2D와 구분

| 구분 | Vision 2D | Vision 3D |
|---|---|---|
| 요청 | `VNDetectHumanBodyPoseRequest` | `VNDetectHumanBodyPose3DRequest` |
| 출력 | 최대 19개 정규화 2D point | 17개 3D joint skeleton |
| 사람 수 | 여러 observation 가능 | 초기 revision의 가장 두드러진 한 사람 |
| 품질 | per-joint confidence | observation-level confidence, per-joint confidence 없음 |
| 현재 상태 | PoseNet fallback | 제외 |

## 참고 자료

- Apple “Identifying 3D human body poses in images”: <https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images>
- Apple `VNDetectHumanBodyPose3DRequest`: <https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest>
- Apple `VNHumanBodyPose3DObservation`: <https://developer.apple.com/documentation/vision/vnhumanbodypose3dobservation>
- WWDC23 “Explore 3D body pose and person segmentation in Vision”: <https://developer.apple.com/videos/play/wwdc2023/111241/>
