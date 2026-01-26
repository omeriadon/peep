//
//  ContentView.swift
//  Peep
//
//  Created by Adon Omeri on 25/1/2026.
//

import AVFoundation
import SwiftUI

struct ContentView: View {
	@StateObject private var camera = CameraStreamController()

	var body: some View {
		ZStack {
			CameraPreviewView(session: camera.session)
				.ignoresSafeArea()

			VStack {
				Spacer()
				Text(camera.isRunning ? "STREAMING" : "STOPPED")
					.foregroundStyle(.white)
					.padding(.bottom, 30)
			}
		}
		.onAppear {
			WCSessionManager.shared.start()
			camera.start()
		}
		.onDisappear {
			camera.stop()
		}
	}
}

struct CameraPreviewView: UIViewRepresentable {
	let session: AVCaptureSession

	func makeUIView(context _: Context) -> UIView {
		let view = UIView()
		let layer = AVCaptureVideoPreviewLayer(session: session)
		layer.videoGravity = .resizeAspectFill
		layer.frame = view.bounds
		view.layer.addSublayer(layer)
		return view
	}

	func updateUIView(_ uiView: UIView, context _: Context) {
		uiView.layer.sublayers?.first?.frame = uiView.bounds
	}
}
