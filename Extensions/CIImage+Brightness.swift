import CoreImage
import UIKit

extension CIImage {
    /// Computes average brightness of an image region
    func averageBrightness() -> CGFloat {
        let extentVector = CIVector(x: extent.origin.x,
                                    y: extent.origin.y,
                                    z: extent.size.width,
                                    w: extent.size.height)

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: self,
            kCIInputExtentKey: extentVector
        ]),
        let outputImage = filter.outputImage else {
            return 0.0
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext()
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0

        return (r + g + b) / 3.0
    }
}
