//
//  ContentView.swift
//  PeepWatch Watch App
//
//  Created by Adon Omeri on 25/1/2026.
//

import SwiftUI

struct ContentView: View {
	@StateObject private var viewModel = CameraNavigatorViewModel()
	@Environment(\.isLuminanceReduced) private var isAlwaysOn
	@State private var displayedImage: UIImage?

	@FocusState private var crownFocused: Bool

	var body: some View {
		NavigationStack {
			GeometryReader { geo in
				ZStack(alignment: .center) {
					if let img = displayedImage {
						Image(uiImage: img)
							.resizable()
							.interpolation(.high)
							.aspectRatio(contentMode: .fit)
							.frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
							.scaleEffect(viewModel.zoom)
							.offset(viewModel.offset)
							.gesture(dragGesture)
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
							.ignoresSafeArea()

					} else {
						Text("Waiting for image...")
							.font(.footnote)
					}
					if viewModel.isSignalStale {
						Text("Stale Signal")
							.font(.headline)
							.foregroundColor(.white)
							.padding(5)
							.glassEffect(.clear.tint(.red).interactive())
							.glassEffectTransition(.materialize)
					}
				}
			}
			.onReceive(viewModel.$currentImage) { img in
				displayedImage = img
			}
			.toolbar {
				ToolbarItem(placement: .bottomBar) {
					Button(action: viewModel.cycleLens) {
						Text(viewModel.lensButtonTitle)
							.font(.caption)
							.padding(5)
							.glassEffect(.clear.interactive())
					}
					.buttonStyle(.plain)
				}

				ToolbarItem(placement: .bottomBar) {
					Text(viewModel.zoomLabel)
						.font(.caption)
				}
			}
			.onAppear { crownFocused = true }
		}
	}

	private var dragGesture: some Gesture {
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
	}
}
