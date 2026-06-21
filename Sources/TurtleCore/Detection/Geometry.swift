import Foundation

public enum Geometry {
    /// 구버전 측면 각(`abs`로 비단조 — I-1). 런타임은 `monotonicProfileAngle`을 쓰며 이 함수는 회귀 테스트용으로만 남아 있다.
    public static func cvaAngleDegrees(head: Point2D, shoulder: Point2D) -> Double {
        let dx = abs(head.x - shoulder.x)
        let dy = abs(shoulder.y - head.y)
        let radians = atan2(dy, dx)
        return radians * 180 / .pi
    }

    /// 부호 보존(단조) 측면 각. 좌표는 y 아래로 증가하므로 머리가 어깨 위에 있을 때만 vertical>0.
    /// 머리가 어깨선 아래로 내려가면 vertical=0 → 각이 0°로 단조 감소(거북목→정상 오판 방지, I-1).
    public static func monotonicProfileAngle(head: Point2D, shoulder: Point2D) -> Double {
        let dx = abs(head.x - shoulder.x)
        let vertical = max(0, shoulder.y - head.y)
        return atan2(vertical, dx) * 180 / .pi
    }

    /// 신체 좌표계(어깨선·torso) 기준 머리-몸통 시상각. 카메라 좌표가 아닌 body-frame에 투영해 시점에 강건하다.
    /// forward 부호 보존(앞=거북목 방향). 머리가 어깨 위(vertical>0.05)일 때만 평가한다.
    public static func bodySagittalAngleDegrees(from pose: Pose3D) -> Double? {
        guard
            let frame = BodyFrame(pose: pose),
            let head = (pose.centerHead?.isTrackable == true ? pose.centerHead : pose.topHead),
            head.isTrackable
        else {
            return nil
        }

        let headVector = Vector3(head) - frame.origin
        let vertical = headVector.dot(frame.up)
        guard vertical > 0.05 else {
            return nil
        }
        let forward = headVector.dot(frame.forward)
        return atan2(vertical, forward) * 180 / .pi
    }

    /// 이마-몸통 전방 깊이차를 어깨폭으로 정규화(PreventFHP식). 양수=머리가 앞. 단안 깊이라 baseline 상대화가 전제.
    public static func forwardDepthDeltaNormalized(from pose: Pose3D) -> Double? {
        guard
            let frame = BodyFrame(pose: pose),
            let head = (pose.centerHead?.isTrackable == true ? pose.centerHead : pose.topHead),
            head.isTrackable,
            frame.shoulderWidth > 0.05
        else {
            return nil
        }

        return (Vector3(head) - frame.shoulderCenter).dot(frame.forward) / frame.shoulderWidth
    }
}

private struct BodyFrame {
    let origin: Vector3
    let shoulderCenter: Vector3
    let shoulderWidth: Double
    let up: Vector3
    let forward: Vector3

    init?(pose: Pose3D) {
        guard
            let leftShoulder = pose.leftShoulder, leftShoulder.isTrackable,
            let rightShoulder = pose.rightShoulder, rightShoulder.isTrackable
        else {
            return nil
        }

        let left = Vector3(leftShoulder)
        let right = Vector3(rightShoulder)
        let shoulderAxis = right - left
        shoulderWidth = shoulderAxis.length
        guard shoulderWidth > 0.05, let rightAxis = shoulderAxis.normalized else {
            return nil
        }

        shoulderCenter = (left + right) * 0.5
        let worldUp = Vector3(x: 0, y: 1, z: 0)
        if let spine = pose.spine, spine.isTrackable, let torsoUp = (shoulderCenter - Vector3(spine)).normalized {
            up = torsoUp
            origin = Vector3(spine)
        } else {
            up = worldUp
            origin = shoulderCenter
        }

        // forward = lateral × up. 좌우 어깨 순서·미러링에 따라 부호가 뒤집힐 수 있어, 절대 전/후 판정보다 baseline 상대화에 의존한다.
        guard let forwardAxis = rightAxis.cross(up).normalized else {
            return nil
        }
        forward = forwardAxis
    }
}

private struct Vector3 {
    var x: Double
    var y: Double
    var z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ point: Point3D) {
        self.init(x: point.x, y: point.y, z: point.z)
    }

    var length: Double {
        sqrt(x * x + y * y + z * z)
    }

    var normalized: Vector3? {
        let length = length
        guard length > 0.000_001 else {
            return nil
        }
        return self * (1 / length)
    }

    func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static func * (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }
}
