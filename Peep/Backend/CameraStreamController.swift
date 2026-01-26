//
//  CameraStreamController.swift
//  Peep
//

import AVFoundation
import Combine
import CoreImage
import UIKit

final class CameraStreamController: NSObject, ObservableObject {

	private let session = AVCaptureSession()
	private let output = AVCaptureVideoDataOutput()
	private let queue = DispatchQueue(label: "camera.queue")

	private let previewLayer: AVCaptureVideoPreviewLayer
	private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
	private var rotationObservation: NSKeyValueObservation?

	private var lastSent: CFTimeInterval = 0
	private let fps: Double = 8
	
	private var currentDevice: AVCaptureDevice?
	private var cancellables = Set<AnyCancellable>()
	private let lensMetadata: [LensMetadata]
	private let availableLensNames: Set<String>

	override init() {
		self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
		self.lensMetadata = Self.detectLensMetadata()
		self.availableLensNames = Set(lensMetadata.map { $0.name })

		super.init()
		configure()
		configureRotation()
		observeLensRequests()
		WCSessionManager.shared.updateAvailableLensPayload(lensMetadata.map { $0.dictionary })
	}

	private func configure() {
		session.beginConfiguration()
		session.sessionPreset = .high

		guard
			let device = AVCaptureDevice.default(.builtInWideAngleCamera,
				for: .video,
				position: .back),
			let input = try? AVCaptureDeviceInput(device: device),
			session.canAddInput(input)
		else {
			session.commitConfiguration()
			return
		}

		currentDevice = device
		session.addInput(input)

		output.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey as String:
				kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
		]
		output.alwaysDiscardsLateVideoFrames = true
		output.setSampleBufferDelegate(self, queue: queue)

		if session.canAddOutput(output) {
			session.addOutput(output)
		}

		session.commitConfiguration()
	}

	private func configureRotation() {
		guard let input = session.inputs.first as? AVCaptureDeviceInput else { return }

		let coordinator = AVCaptureDevice.RotationCoordinator(
			device: input.device,
			previewLayer: previewLayer
		)
		self.rotationCoordinator = coordinator

		self.rotationObservation = coordinator.observe(
			\.videoRotationAngleForHorizonLevelCapture,
			options: NSKeyValueObservingOptions([.initial, .new])
		) { [weak self] (_: AVCaptureDevice.RotationCoordinator,
		  change: NSKeyValueObservedChange<CGFloat>) in
			guard
				let self,
				let angle = change.newValue
			else { return }

			for connection in self.output.connections {
				if connection.isVideoRotationAngleSupported(angle) {
					connection.videoRotationAngle = angle
				}
			}
		}
	}
	
	private func observeLensRequests() {
		WCSessionManager.shared.$requestedLens
			.compactMap { $0 }
			.removeDuplicates()
			.sink { [weak self] lens in
				self?.switchLens(lens)
			}
			.store(in: &cancellables)
	}
	
	private func switchLens(_ lens: String) {
		guard availableLensNames.contains(lens), let lensType = LensType(rawValue: lens) else { return }
		
		session.beginConfiguration()
		
		guard
			let newDevice = AVCaptureDevice.default(lensType.deviceType, for: .video, position: .back),
			let newInput = try? AVCaptureDeviceInput(device: newDevice)
		else {
			session.commitConfiguration()
			return
		}
		
		if let oldInput = session.inputs.first as? AVCaptureDeviceInput {
			session.removeInput(oldInput)
		}
		
		if session.canAddInput(newInput) {
			session.addInput(newInput)
			currentDevice = newDevice
			configureRotation()
		}
		
		session.commitConfiguration()
	}

	func start() {
		UIApplication.shared.isIdleTimerDisabled = true
		session.startRunning()
	}

	func stop() {
		UIApplication.shared.isIdleTimerDisabled = false
		session.stopRunning()
	}
}

// MARK: - Lens metadata helpers

private extension CameraStreamController {
	struct LensMetadata {
		let lensType: LensType
		let zoom: CGFloat

		var name: String { lensType.rawValue }
		var dictionary: [String: Any] {
			let formattedZoom = String(format: "%.1fx", zoom)
			return [
				"name": name,
				"displayName": "\(lensType.displayName) (\(formattedZoom))",
				"zoom": Double(zoom)
			]
		}
	}

	enum LensType: String, CaseIterable {
		case wide
		case ultrawide
		case tele

		var deviceType: AVCaptureDevice.DeviceType {
			switch self {
			case .wide:
				return .builtInWideAngleCamera
			case .ultrawide:
				return .builtInUltraWideCamera
			case .tele:
				return .builtInTelephotoCamera
			}
		}

		var displayName: String {
			switch self {
			case .wide:
				return "Wide"
			case .ultrawide:
				return "Ultra Wide"
			case .tele:
				return "Telephoto"
			}
		}
	}

	static func detectLensMetadata() -> [LensMetadata] {
		let baseDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
			?? LensType.allCases.compactMap { AVCaptureDevice.default($0.deviceType, for: .video, position: .back) }.first
		let baseFocal = baseDevice.flatMap { focalLength(for: $0) } ?? 1.0

		var lenses = [LensMetadata]()
		for lensType in LensType.allCases {
			guard let device = AVCaptureDevice.default(lensType.deviceType, for: .video, position: .back),
				let zoom = zoomFactor(for: device, relativeTo: baseFocal)
			else { continue }
			lenses.append(LensMetadata(lensType: lensType, zoom: zoom))
		}

		if lenses.isEmpty {
			lenses.append(LensMetadata(lensType: .wide, zoom: 1.0))
		}

		return lenses.sorted { $0.zoom < $1.zoom }
	}

	static func focalLength(for device: AVCaptureDevice) -> CGFloat? {
		let fov = device.activeFormat.videoFieldOfView
		let radians = CGFloat(fov) * .pi / 180
		guard radians > 0 else { return nil }
		return CGFloat(35.0 / (2.0 * tan(radians / 2)))
	}

	static func zoomFactor(for device: AVCaptureDevice, relativeTo baseFocal: CGFloat) -> CGFloat? {
		guard let focal = focalLength(for: device), baseFocal > 0 else { return nil }
		return focal / baseFocal
	}
}
extension CameraStreamController: AVCaptureVideoDataOutputSampleBufferDelegate {

	func captureOutput(
		_: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from _: AVCaptureConnection
	) {
		let now = CACurrentMediaTime()
		guard now - lastSent >= 1 / fps else { return }
		lastSent = now

		guard WCSessionManager.shared.reachable else { return }
		guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

		let ci = CIImage(cvPixelBuffer: pb)
		guard let data = HEICEncoder.encode(ciImage: ci) else { return }

		WCSessionManager.shared.sendFrame(
			data,
			timestamp: Date().timeIntervalSince1970
		)
	}
}
