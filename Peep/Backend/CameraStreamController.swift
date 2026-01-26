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
	private let fps: Double = 10

	override init() {
		self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
		super.init()
		configure()
		configureRotation()
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
