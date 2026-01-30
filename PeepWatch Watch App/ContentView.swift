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
            GeometryReader { _ in
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
}
