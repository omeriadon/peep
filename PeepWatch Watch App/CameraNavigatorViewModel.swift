//
//  CameraNavigatorViewModel.swift
//  PeepWatch Watch App
//
//  Created by Adon Omeri on 26/1/2026.
//

import Foundation
import Combine
import UIKit

final class CameraNavigatorViewModel: ObservableObject {
	@Published var currentImage: UIImage?
	@Published var zoom: CGFloat = 1.0
	@Published var offset: CGSize = .zero
	@Published var baseOffset: CGSize = .zero

	var lastTimestamp: TimeInterval? {
		WatchSessionManager.shared.lastTimestamp
	}

	private let lensBreakpoints: [CGFloat: String] = [
		1.0: "wide",
		1.5: "ultrawide",
		2.5: "tele"
	]
	private var currentLens: String = "wide"
	private var hasReportedInitialFrame = false

	var maxZoom: CGFloat { 3.0 }

	private var cancellables = Set<AnyCancellable>()

	init() {
		let manager = WatchSessionManager.shared

		manager.$image
			.receive(on: DispatchQueue.main)
			.sink { [weak self] img in
				guard let self = self else { return }
				let hadFrame = self.hasReportedInitialFrame
				self.currentImage = img
				if img != nil {
					if !hadFrame {
						self.hasReportedInitialFrame = true
						self.resetTransforms()
					}
				} else {
					self.hasReportedInitialFrame = false
					self.resetTransforms()
				}
			}
			.store(in: &cancellables)

		manager.$lastTimestamp
			.receive(on: DispatchQueue.main)
			.sink { _ in }
			.store(in: &cancellables)
	}

	func updateLensIfNeeded() {
		let targetLens = lensForZoom(zoom)
		if targetLens != currentLens {
			WatchSessionManager.shared.requestLens(targetLens)
			currentLens = targetLens
		}
	}

	private func lensForZoom(_ zoom: CGFloat) -> String {
		var selected = "wide"
		for (breakpoint, lens) in lensBreakpoints.sorted(by: { $0.key < $1.key }) {
			if zoom >= breakpoint {
				selected = lens
			}
		}
		return selected
	}

	private func resetTransforms() {
		zoom = 1.0
		offset = .zero
		baseOffset = .zero
	}
}
