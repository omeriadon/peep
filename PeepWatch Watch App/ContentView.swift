//
//  ContentView.swift
//  PeepWatch Watch App
//
//  Created by Adon Omeri on 25/1/2026.
//

import SwiftUI
import Combine

struct ContentView: View {
	@StateObject private var wc = WatchSessionManager()

 var body: some View {
	 Group {
		 if let image = wc.image {
			 Image(uiImage: image)
				 .resizable()
				 .scaledToFit()
		 } else {
			 Color.black
		 }
	 }
 }
}
