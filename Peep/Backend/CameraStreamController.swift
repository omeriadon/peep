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
	private let availableLenses: Set<String>

	override init() {
		self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
		
		var lenses = Set<String>()
		if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
			lenses.insert("wide")
		}
		if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil {
			lenses.insert("ultrawide")
		}
		if AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil {
			lenses.insert("tele")
		}
		self.availableLenses = lenses
		
		super.init()
		configure()
		configureRotation()
		observeLensRequests()
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
		guard availableLenses.contains(lens) else { return }
		
		session.beginConfiguration()
		
		let deviceType: AVCaptureDevice.DeviceType
		switch lens {
		case "ultrawide":
			deviceType = .builtInUltraWideCamera
		case "tele":
			deviceType = .builtInTelephotoCamera
		default:
			deviceType = .builtInWideAngleCamera
		}
		
		guard
			let newDevice = AVCaptureDevice.default(deviceType, for: .video, position: .back),
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
		guard let data = JPEGEncoder.encode(ciImage: ci) else { return }

		WCSessionManager.shared.sendFrame(
			data,
			timestamp: Date().timeIntervalSince1970
		)
	}
}
