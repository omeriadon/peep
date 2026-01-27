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
	private let discoveredDevices: [AVCaptureDevice]
	private let lensMetadata: [LensMetadata]
	private let availableLensNames: Set<String>

	override init() {
		let discoveredDevices = Self.discoverAllDevices()
		previewLayer = AVCaptureVideoPreviewLayer(session: session)
		self.discoveredDevices = discoveredDevices
		lensMetadata = Self.detectLensMetadata(from: discoveredDevices)
		availableLensNames = Set(lensMetadata.map { $0.name })

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
			let device = preferredInitialDevice(),
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
				kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
		]
		output.alwaysDiscardsLateVideoFrames = true
		output.setSampleBufferDelegate(self, queue: queue)

		if session.canAddOutput(output) {
			session.addOutput(output)
		}

		session.commitConfiguration()
	}

	private func preferredInitialDevice() -> AVCaptureDevice? {
		discoveredDevices.first(where: { $0.position == .back && $0.deviceType == .builtInWideAngleCamera }) ??
			discoveredDevices.first(where: { $0.position == .back }) ??
			discoveredDevices.first
	}

	private func configureRotation() {
		guard let input = session.inputs.first as? AVCaptureDeviceInput else { return }

		let coordinator = AVCaptureDevice.RotationCoordinator(
			device: input.device,
			previewLayer: previewLayer
		)
		rotationCoordinator = coordinator

		rotationObservation = coordinator.observe(
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
		guard let metadata = lensMetadata.first(where: { $0.name == lens }) else { return }

		session.beginConfiguration()

		guard let newInput = try? AVCaptureDeviceInput(device: metadata.device) else {
			session.commitConfiguration()
			return
		}

		if let oldInput = session.inputs.first as? AVCaptureDeviceInput {
			session.removeInput(oldInput)
		}

		if session.canAddInput(newInput) {
			session.addInput(newInput)
			currentDevice = metadata.device
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

private extension CameraStreamController {
	struct LensMetadata {
		let device: AVCaptureDevice
		let lensType: LensType
		let zoom: CGFloat

		var name: String { lensType.rawValue }
		var dictionary: [String: Any] {
			let formattedZoom = String(format: "%.1fx", zoom)
			return [
				"name": name,
				"displayName": "\(lensType.displayName) (\(formattedZoom))",
				"zoom": Double(zoom),
			]
		}
	}

	enum LensType: String, CaseIterable {
		case front
		case ultrawide
		case wide
		case tele
		case tele2

		var deviceType: AVCaptureDevice.DeviceType {
			switch self {
				case .front: return .builtInWideAngleCamera
				case .ultrawide: return .builtInUltraWideCamera
				case .wide: return .builtInWideAngleCamera
				case .tele: return .builtInTelephotoCamera
				case .tele2: return .builtInTelephotoCamera
			}
		}

		var position: AVCaptureDevice.Position {
			self == .front ? .front : .back
		}

		var displayName: String {
			switch self {
				case .front: return "Front"
				case .ultrawide: return "Ultra Wide"
				case .wide: return "Wide"
				case .tele: return "Telephoto"
				case .tele2: return "Telephoto 2"
			}
		}
	}

	static func discoverAllDevices() -> [AVCaptureDevice] {
		let discovery = AVCaptureDevice.DiscoverySession(
			deviceTypes: [
				.builtInWideAngleCamera,
				.builtInUltraWideCamera,
				.builtInTelephotoCamera,
			],
			mediaType: .video,
			position: .unspecified
		)
		return discovery.devices
	}

	static func detectLensMetadata(from devices: [AVCaptureDevice]) -> [LensMetadata] {
		let backWide = devices.first { $0.position == .back && $0.deviceType == .builtInWideAngleCamera }
		let baseFocal = backWide.flatMap { focalLength(for: $0) } ?? 1.0

		var lenses = [LensMetadata]()
		var usedDevices = Set<String>()

		for lensType in LensType.allCases {
			let candidates = devices.filter {
				$0.position == lensType.position &&
					$0.deviceType == lensType.deviceType &&
					!usedDevices.contains($0.uniqueID)
			}

			for device in candidates.sorted(by: { focalLength(for: $0) ?? 0 < focalLength(for: $1) ?? 0 }) {
				let zoom: CGFloat
				if device.position == .front {
					zoom = (focalLength(for: device) ?? baseFocal) / baseFocal
				} else {
					zoom = zoomFactor(for: device, relativeTo: baseFocal) ?? 1.0
				}
				lenses.append(LensMetadata(device: device, lensType: lensType, zoom: zoom))
				usedDevices.insert(device.uniqueID)
			}
		}

		if lenses.isEmpty {
			if let fallback = devices.first {
				lenses.append(LensMetadata(device: fallback, lensType: .wide, zoom: 1.0))
			}
		}

		return lenses
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
