//
//  CameraStreamer.swift
//  Peep
//
//  Created by Adon Omeri on 25/1/2026.
//

import Foundation
import WatchConnectivity
import AVFoundation
import UIKit
import Combine

final class WCSessionManager: NSObject, WCSessionDelegate {
	static let shared = WCSessionManager()
	override private init() { super.init() }

	func start() {
		guard WCSession.isSupported() else { return }
		let session = WCSession.default
		session.delegate = self
		session.activate()
		print("[iPhone] WCSession activated")
	}

	func sendFrame(_ jpegData: Data) {
		let sizeKB = jpegData.count / 1024
		print("[iPhone] Frame size:", sizeKB, "KB")

		guard jpegData.count <= 65000 else {
			print("[iPhone] Frame dropped (too large)")
			return
		}

		WCSession.default.sendMessage(
			["frame": jpegData],
			replyHandler: nil,
			errorHandler: { error in
				print("[iPhone] sendMessage error:", error)
			}
		)
	}

	// Required stubs
	func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}
	func sessionDidBecomeInactive(_: WCSession) {}
	func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}


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
				kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
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
		_ output: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from connection: AVCaptureConnection
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
