import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers

extension CGImage {
    func resized(toMaxWidth maxWidth: CGFloat) -> CGImage? {
        let currentWidth = CGFloat(self.width)
        guard currentWidth > maxWidth else { return self }
        let scale = maxWidth / currentWidth
        let newWidth = Int(currentWidth * scale)
        let newHeight = Int(CGFloat(self.height) * scale)
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: self.bitsPerComponent,
            bytesPerRow: 0, space: self.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: self.bitmapInfo.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    func jpegData(quality: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    func webpData(quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.webP.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, self, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func resized(toFit maxDimension: CGFloat) -> CGImage? {
        let currentWidth = CGFloat(self.width)
        let currentHeight = CGFloat(self.height)
        let largerDimension = max(currentWidth, currentHeight)
        guard largerDimension > maxDimension else { return self }
        let scale = maxDimension / largerDimension
        let newWidth = Int(currentWidth * scale)
        let newHeight = Int(currentHeight * scale)
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: self.bitsPerComponent,
            bytesPerRow: 0, space: self.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: self.bitmapInfo.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}
