import Foundation

public enum Geometry {
    public static func cvaAngleDegrees(head: Point2D, shoulder: Point2D) -> Double {
        let dx = abs(head.x - shoulder.x)
        let dy = abs(shoulder.y - head.y)
        let radians = atan2(dy, dx)
        return radians * 180 / .pi
    }

    public static func bodySagittalAngleDegrees(from pose: Pose3D) -> Double? {
        guard
            let left = pose.leftShoulder, left.isReliable,
            let right = pose.rightShoulder, right.isReliable,
            let head = pose.centerHead?.isReliable == true ? pose.centerHead : pose.topHead,
            head.isReliable
        else {
            return nil
        }

        let leftV = Vector3(left)
        let rightV = Vector3(right)
        let headV = Vector3(head)
        let shoulderCenter = (leftV + rightV) * 0.5

        guard let lateral = (rightV - leftV).normalized() else {
            return nil
        }

        let lowerBody = pose.spine?.isReliable == true
            ? pose.spine
            : (pose.root?.isReliable == true ? pose.root : nil)
        let bodyUp = lowerBody.flatMap { (shoulderCenter - Vector3($0)).normalized() } ?? Vector3(x: 0, y: 1, z: 0)
        guard let forward = lateral.cross(bodyUp).normalized() else {
            return nil
        }

        let headVector = headV - shoulderCenter
        let up = abs(headVector.dot(bodyUp))
        let forwardDistance = abs(headVector.dot(forward))
        return atan2(up, forwardDistance) * 180 / .pi
    }
}

private struct Vector3 {
    var x: Double
    var y: Double
    var z: Double

    init(_ point: Point3D) {
        x = point.x
        y = point.y
        z = point.z
    }

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
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

    func normalized() -> Vector3? {
        let length = sqrt(x * x + y * y + z * z)
        guard length > 0.000001 else {
            return nil
        }
        return Vector3(x: x / length, y: y / length, z: z / length)
    }
}
