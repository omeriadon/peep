//
//  ContentView.swift
//  PeepWatch Watch App
//
//  Created by Adon Omeri on 25/1/2026.
//

import SwiftUI

struct ContentView: View {
	@StateObject private var viewModel = CameraNavigatorViewModel()
	@FocusState private var crownFocused: Bool

	var body: some View {
		NavigationStack {
			GeometryReader { geo in
				ZStack {
					if let uiImage = viewModel.currentImage {
						Image(uiImage: uiImage)
							.resizable()
							.ignoresSafeArea(.all)
							.frame(width: geo.size.width, height: geo.size.height)
							.aspectRatio(contentMode: .fit)
							.scaleEffect(viewModel.zoom)
							.offset(viewModel.offset)
							.gesture(
								DragGesture()
									.onChanged { value in
										viewModel.offset = CGSize(
											width: viewModel.baseOffset.width + value.translation.width,
											height: viewModel.baseOffset.height + value.translation.height
										)
									}
									.onEnded { value in
										viewModel.baseOffset = CGSize(
											width: viewModel.baseOffset.width + value.translation.width,
											height: viewModel.baseOffset.height + value.translation.height
										)
									}
							)
							.focusable(true)
							.focused($crownFocused)
							.digitalCrownRotation(
								$viewModel.zoom,
								from: viewModel.zoomRange.lowerBound,
								through: viewModel.zoomRange.upperBound,
								by: 0.05,
								sensitivity: .medium,
								isContinuous: false,
								isHapticFeedbackEnabled: true
							)
							.digitalCrownAccessory {
								Text(viewModel.zoomLabel)
							}

					} else {
						VStack {
							Text("Waiting for image...")
								.font(.footnote)
							if let lastTime = viewModel.lastTimestamp {
								Text("Last update: \(Int(Date().timeIntervalSince1970 - lastTime))s ago")
									.font(.caption2)
							}
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
					}
					if viewModel.isSignalStale {
						Text("NO SIGNAL")
							.font(.headline)
							.foregroundColor(.white)
							.ignoresSafeArea()
					}
				}
				.ignoresSafeArea()
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button(action: viewModel.cycleLens) {
						Text(viewModel.lensButtonTitle)
					}
				}
			}
		}
		.onAppear {
			crownFocused = true
		}
	}
}
