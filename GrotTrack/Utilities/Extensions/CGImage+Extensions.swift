import CoreGraphics
import AppKit
import libwebp

extension CGImage {
    static func load(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }


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
        let width = self.width
        let height = self.height
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let pixelData = context.data else { return nil }

        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        let bgra = pixelData.assumingMemoryBound(to: UInt8.self)
        var output: UnsafeMutablePointer<UInt8>?
        let size = WebPEncodeBGRA(bgra, Int32(width), Int32(height), Int32(bytesPerRow), Float(quality * 100), &output)

        guard size > 0, let output else { return nil }
        let data = Data(bytes: output, count: Int(size))
        WebPFree(output)
        return data
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
