import CoreMedia
import CoreVideo
import Foundation

public enum CameraFrameQuality {
    public static func isUsable(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return isUsableLumaPlane(pixelBuffer)
        case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32ARGB, kCVPixelFormatType_32RGBA:
            return isUsableRGB(pixelBuffer, pixelFormat: pixelFormat)
        default:
            return false
        }
    }

    private static func isUsableLumaPlane(_ pixelBuffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return false
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        return isUsableSampleGrid(width: width, height: height) { x, y in
            let row = base.advanced(by: y * bytesPerRow)
            return Double(row.assumingMemoryBound(to: UInt8.self)[x])
        }
    }

    private static func isUsableRGB(_ pixelBuffer: CVPixelBuffer, pixelFormat: OSType) -> Bool {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return false
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        return isUsableSampleGrid(width: width, height: height) { x, y in
            let row = base.advanced(by: y * bytesPerRow)
            let pixel = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
            let red: UInt8
            let green: UInt8
            let blue: UInt8
            switch pixelFormat {
            case kCVPixelFormatType_32ARGB:
                red = pixel[1]
                green = pixel[2]
                blue = pixel[3]
            case kCVPixelFormatType_32RGBA:
                red = pixel[0]
                green = pixel[1]
                blue = pixel[2]
            default:
                blue = pixel[0]
                green = pixel[1]
                red = pixel[2]
            }
            return 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        }
    }

    public static func isUsableSampleGrid(
        width: Int,
        height: Int,
        sample: (Int, Int) -> Double
    ) -> Bool {
        guard width > 0, height > 0 else { return false }
        let columns = 12
        let rows = 8
        var total = 0.0
        var maximum = 0.0
        for row in 0..<rows {
            let y = min(height - 1, row * height / rows)
            for column in 0..<columns {
                let x = min(width - 1, column * width / columns)
                let value = sample(x, y)
                total += value
                maximum = max(maximum, value)
            }
        }
        let average = total / Double(columns * rows)
        return maximum >= 24 || average >= 8
    }
}
