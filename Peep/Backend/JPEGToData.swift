//
//  JPEGToData.swift
//  Peep
//
//  Created by Adon Omeri on 26/1/2026.
//

import AVFoundation
import UIKit

func jpegData(
	from pixelBuffer: CVPixelBuffer,
	maxWidth: CGFloat = 500,
	quality: CGFloat = 0.3
) -> Data? {
	let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

	let scale = maxWidth / ciImage.extent.width
	let resized = ciImage.transformed(by: .init(scaleX: scale, y: scale))

	let context = CIContext()
	guard let cgImage = context.createCGImage(resized, from: resized.extent) else {
		return nil
	}

	let uiImage = UIImage(cgImage: cgImage)

	return uiImage.jpegData(compressionQuality: quality)
}
