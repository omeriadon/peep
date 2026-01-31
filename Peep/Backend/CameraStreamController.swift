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
		availableLensNames = Set(lensMetadata.map(\.name))

		super.init()
		configure()
		configureRotation()
		observeLensRequests()
		WCSessionManager.shared.updateAvailableLensPayload(lensMetadata.map(\.dictionary))
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

				for connection in output.connections {
					if connection.isVideoRotationAngleSupported(angle) {
						connection.videoRotationAngle = angle
					}
				}
		}
	}

	private func observeLensRequests() {
		WCSessionManager.shared.$requestedLens
			.compactMap(\.self)
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
		let name: String
		let displayName: String
		let zoom: CGFloat

		var dictionary: [String: Any] {
			[
				"name": name,
				"displayName": displayName,
				"zoom": Double(zoom),
			]
		}
	}

	static func discoverAllDevices() -> [AVCaptureDevice] {
		let backSession = AVCaptureDevice.DiscoverySession(
			deviceTypes: [
				.builtInTripleCamera,
				.builtInDualWideCamera,
				.builtInDualCamera,
				.builtInWideAngleCamera,
			],
			mediaType: .video,
			position: .back
		)

		let frontSession = AVCaptureDevice.DiscoverySession(
			deviceTypes: [.builtInWideAngleCamera],
			mediaType: .video,
			position: .front
		)

		return backSession.devices + frontSession.devices
	}

	static func detectLensMetadata(from devices: [AVCaptureDevice]) -> [LensMetadata] {
		let backWide = devices.first { $0.position == .back && $0.deviceType == .builtInWideAngleCamera }
		let baseFocal = backWide.flatMap { focalLength(for: $0) } ?? 1.0

		var seen = Set<String>()
		var lenses = [LensMetadata]()

		for device in devices {
			guard !seen.contains(device.uniqueID) else { continue }
			seen.insert(device.uniqueID)

			let focal = focalLength(for: device) ?? baseFocal
			let zoom = focal / baseFocal
			let name = lensName(for: device, zoom: zoom)
			let display = lensDisplayName(for: device, zoom: zoom)

			lenses.append(LensMetadata(
				device: device,
				name: name,
				displayName: display,
				zoom: zoom
			))
		}

		return lenses
	}

	static func lensName(for device: AVCaptureDevice, zoom: CGFloat) -> String {
		if device.position == .front { return "front" }

		switch device.deviceType {
			case .builtInUltraWideCamera: return "ultrawide"
			case .builtInTelephotoCamera:
				return zoom > 3.0 ? "tele2" : "tele"
			default: return "wide"
		}
	}

	static func lensDisplayName(for device: AVCaptureDevice, zoom: CGFloat) -> String {
		let formatted = String(format: "%.1fx", zoom)
		if device.position == .front { return "Front (\(formatted))" }

		switch device.deviceType {
			case .builtInUltraWideCamera: return "Ultra Wide (\(formatted))"
			case .builtInTelephotoCamera: return "Telephoto (\(formatted))"
			default: return "Wide (\(formatted))"
		}
	}

	static func focalLength(for device: AVCaptureDevice) -> CGFloat? {
		let fov = device.activeFormat.videoFieldOfView
		let radians = CGFloat(fov) * .pi / 180
		guard radians > 0 else { return nil }
		return CGFloat(35.0 / (2.0 * tan(radians / 2)))
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
