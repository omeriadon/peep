//
//  ContentView.swift
//  PeepWatch Watch App
//
//  Created by Adon Omeri on 25/1/2026.
//

import SwiftUI

struct ContentView: View {
	@StateObject private var session = WatchSessionManager()

	var body: some View {
		ZStack {
			if let img = session.image {
				Image(uiImage: img)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.ignoresSafeArea(.all)
					.frame(maxWidth: .infinity, maxHeight: .infinity)

			} else {
				Color.clear
			}

			if session.isStale {
				Text("NO SIGNAL")
					.foregroundColor(.white)
					.font(.largeTitle)
			}
		}
		.ignoresSafeArea(edges: .all)
	}
}
