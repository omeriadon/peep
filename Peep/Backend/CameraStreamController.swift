//
//  CameraStreamController.swift
//  Peep
//
//  Created by Adon Omeri on 26/1/2026.
//

import AVFoundation
import Foundation
import Combine

final class CameraStreamController: NSObject, ObservableObject {
	let session = AVCaptureSession()
	private let output = AVCaptureVideoDataOutput()
	private let queue = DispatchQueue(label: "camera.queue")

	private var lastSent = CACurrentMediaTime()
	private let targetFPS: Double = 10

	@Published var isRunning = false

	override init() {
		super.init()
		setup()
	}

	private func setup() {
		session.beginConfiguration()
		session.sessionPreset = .high

		// Prefer ultra-wide
		let device =
			AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
				?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

		guard let cam = device,
		      let input = try? AVCaptureDeviceInput(device: cam),
		      session.canAddInput(input)
		else {
			print("[iPhone] Camera setup failed")
			return
		}

		session.addInput(input)

		output.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey as String:
				kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
		]
		output.setSampleBufferDelegate(self, queue: queue)
		output.alwaysDiscardsLateVideoFrames = true

		guard session.canAddOutput(output) else {
			print("[iPhone] Cannot add output")
			return
		}

		session.addOutput(output)
		session.commitConfiguration()

		print("[iPhone] Camera configured:", cam.deviceType)
	}

	func start() {
		guard !session.isRunning else { return }
		session.startRunning()
		isRunning = true
		print("[iPhone] Camera started")
	}

	func stop() {
		guard session.isRunning else { return }
		session.stopRunning()
		isRunning = false
		print("[iPhone] Camera stopped")
	}
}

extension CameraStreamController: AVCaptureVideoDataOutputSampleBufferDelegate {
	func captureOutput(
		_: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from _: AVCaptureConnection
	) {
		let now = CACurrentMediaTime()
		guard now - lastSent >= 1.0 / targetFPS else { return }
		lastSent = now

		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
			print("[iPhone] No pixel buffer")
			return
		}

		guard let jpeg = jpegData(from: pixelBuffer) else {
			print("[iPhone] JPEG encode failed")
			return
		}

		WCSessionManager.shared.sendFrame(jpeg)
	}
}
