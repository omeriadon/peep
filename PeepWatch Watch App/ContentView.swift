//
//  ContentView.swift
//  PeepWatch Watch App
//
//  Created by Adon Omeri on 25/1/2026.
//

import Combine
import SwiftUI

struct ContentView: View {
	@StateObject private var viewModel = CameraNavigatorViewModel()
	@Environment(\.isLuminanceReduced) private var isAlwaysOn
	@State private var displayedImage: UIImage?
	@State private var scrollPosition: CGPoint = .zero

	@FocusState private var crownFocused: Bool

	@State private var timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

	@State var isSignalStale = false

	var body: some View {
		NavigationStack {
			ZStack(alignment: .center) {
				if let img = displayedImage {
					ScrollView([.horizontal, .vertical]) {
						Image(uiImage: img)
							.resizable()
							.interpolation(.high)
							.aspectRatio(contentMode: .fit)
							.frame(
								width: img.size.width * viewModel.zoom,
								height: img.size.height * viewModel.zoom
							)
							.id("image")
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
					}
					//					.defaultScrollAnchor(.center)
				} else {
					Text("Waiting for image...")
						.font(.footnote)
				}
				VStack {
					if isSignalStale, displayedImage != nil {
						Text("Stale Signal")
							.font(.headline)
							.foregroundColor(.white)
							.padding(5)
							.glassEffect(.clear.tint(.red).interactive())
							.glassEffectTransition(.materialize)
							.onReceive(timer) { _ in
								isSignalStale = viewModel.isSignalStale
							}
					}
				}
				.animation(.easeInOut, value: viewModel.isSignalStale)
			}

			.onReceive(viewModel.$currentImage) { img in
				displayedImage = img
			}
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(action: viewModel.cycleLens) {
						Text(viewModel.lensButtonTitle)
							.font(.caption2)
							.padding(5)
							.glassEffect(.clear.interactive())
					}
					.buttonStyle(.plain)
				}

				ToolbarItem(placement: .topBarLeading) {
					Text(viewModel.zoomLabel)
						.font(.caption2)
				}
			}
			.onAppear { crownFocused = true }
		}
	}
}
