//
//  CameraNavigatorViewModel.swift
//  PeepWatch Watch App
//

import Combine
import Foundation
import UIKit

final class CameraNavigatorViewModel: ObservableObject {
	@Published var currentImage: UIImage?
	@Published var zoom: CGFloat = 1.0
	@Published var offset: CGSize = .zero
	@Published var baseOffset: CGSize = .zero

	var lastTimestamp: TimeInterval? {
		WatchSessionManager.shared.lastTimestamp
	}

	var zoomLabel: String { String(format: "%.1fx", zoom * 10) }
	private var selectedLensDescriptor: WatchSessionManager.LensDescriptor {
		guard lensDescriptors.indices.contains(selectedLensIndex) else { return WatchSessionManager.LensDescriptor.default }
		return lensDescriptors[selectedLensIndex]
	}

	var lensButtonTitle: String {
		selectedLensDescriptor.displayName.components(separatedBy: " (").first ?? selectedLensDescriptor.displayName
	}

	var zoomRange: ClosedRange<CGFloat> { 0.1 ... 2.0 }
	var isSignalStale: Bool { WatchSessionManager.shared.isStale }

	private var hasReportedInitialFrame = false
	private var cancellables = Set<AnyCancellable>()
	private var lensDescriptors: [WatchSessionManager.LensDescriptor] = [WatchSessionManager.LensDescriptor.default]
	private var selectedLensIndex: Int = 0
	private var selectedLensName: String = WatchSessionManager.LensDescriptor.default.name

	init() {
		let manager = WatchSessionManager.shared

		manager.$image
			.receive(on: DispatchQueue.main)
			.sink { [weak self] img in
				guard let self else { return }
				currentImage = img
				if img != nil, !hasReportedInitialFrame {
					hasReportedInitialFrame = true
					resetTransforms()
				}
			}
			.store(in: &cancellables)

		manager.$lastTimestamp
			.receive(on: DispatchQueue.main)
			.sink { _ in }
			.store(in: &cancellables)

		manager.$lenses
			.receive(on: DispatchQueue.main)
			.sink { [weak self] lenses in
				guard let self else { return }
				let previousLensName = selectedLensName
				lensDescriptors = lenses.isEmpty ? [WatchSessionManager.LensDescriptor.default] : lenses
				if let index = lensDescriptors.firstIndex(where: { $0.name == previousLensName }) {
					selectedLensIndex = index
				} else {
					selectedLensIndex = 0
					selectedLensName = lensDescriptors[selectedLensIndex].name
				}
				requestSelectedLens()
			}
			.store(in: &cancellables)
	}

	func cycleLens() {
		guard !lensDescriptors.isEmpty else { return }
		print(lensDescriptors)
		selectedLensIndex = (selectedLensIndex + 1) % lensDescriptors.count
		selectedLensName = lensDescriptors[selectedLensIndex].name
		requestSelectedLens()
	}

	func fillScale(for image: UIImage, in container: CGSize) -> CGFloat {
		guard container.width > 0, container.height > 0 else { return 1 }
		let imageSize = image.size
		guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
		let widthScale = container.width / imageSize.width
		let heightScale = container.height / imageSize.height
		return max(widthScale, heightScale)
	}

	private func requestSelectedLens() {
		guard lensDescriptors.indices.contains(selectedLensIndex) else { return }
		let descriptor = lensDescriptors[selectedLensIndex]
		selectedLensName = descriptor.name
		WatchSessionManager.shared.requestLens(descriptor.name)
	}

	private func resetTransforms() {
		zoom = 1
		offset = .zero
		baseOffset = .zero
	}
}
