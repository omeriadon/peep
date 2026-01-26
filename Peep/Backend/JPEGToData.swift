//
//  JPEGToData.swift
//  Peep
//
//  Created by Adon Omeri on 26/1/2026.
//

import CoreImage
import UIKit



enum JPEGEncoder {
	static func encode(ciImage: CIImage, maxWidth: CGFloat = 500) -> Data? {
		let cropped = ciImage.cropped(to: ciImage.extent.integral)
		let scale = maxWidth / cropped.extent.width
		let scaled = cropped.transformed(by: .init(scaleX: scale, y: scale))

		let context = CIContext()
		guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
		return UIImage(cgImage: cg).jpegData(compressionQuality: 0.3)
	}
}
