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
	@ObservedObject private var wc = WCSessionManager.shared
	@State private var elapsed: Int = 0
	@State private var timer: Timer?
	@State private var frameCount: Int = 0
	@State private var bytesTransferred: Int = 0

	var body: some View {
		VStack(spacing: 20) {
			VStack(spacing: 8) {
				Text(wc.reachable ? "◉ WATCH CONNECTED" : "○ OPEN WATCH APP")
					.font(.system(.title3, design: .monospaced))
					.foregroundColor(wc.reachable ? .green : .orange)
				
				Text("Streaming: \(elapsed)s")
					.font(.system(.body, design: .monospaced))
			}
			
			Divider()
			
			VStack(alignment: .leading, spacing: 12) {
				InfoRow(label: "Active Lens", value: wc.requestedLens ?? "wide")
				InfoRow(label: "Frame Rate", value: "8 fps")
				InfoRow(label: "Compression", value: "JPEG Q0")
				InfoRow(label: "Max Resolution", value: "700px")
			}
			.padding()
			.background(Color(.systemGray6))
			.cornerRadius(12)
			
			Spacer()
			
			Text("Reframe on Watch")
				.font(.footnote)
				.foregroundColor(.secondary)
		}
		.padding()
		.onAppear {
			WCSessionManager.shared.start()
			camera.start()

			timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
				DispatchQueue.main.async {
					elapsed += 1
				}
			}
		}
		.onDisappear {
			camera.stop()
			timer?.invalidate()
			timer = nil
		}
	}
}

struct InfoRow: View {
	let label: String
	let value: String
	
	var body: some View {
		HStack {
			Text(label)
				.font(.system(.subheadline, design: .monospaced))
				.foregroundColor(.secondary)
			Spacer()
			Text(value)
				.font(.system(.subheadline, design: .monospaced))
				.bold()
		}
	}
}
