//
//  HEICEncoder.swift
//  Peep
//
//  Created by Adon Omeri on 26/1/2026.
//

import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum HEICEncoder {
    static func encode(ciImage: CIImage, maxWidth: CGFloat = 2000) -> Data? {
        let cropped = ciImage.cropped(to: ciImage.extent.integral)
        let width = cropped.extent.width
        let scale = width > 0 ? min(maxWidth / width, 1) : 1
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaled = cropped.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        guard let data = CFDataCreateMutable(kCFAllocatorDefault, 0) else { return nil }
        guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0,
            kCGImageDestinationImageMaxPixelSize: max(scaled.extent.width, scaled.extent.height),
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
