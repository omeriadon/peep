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

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text(wc.reachable ? "◉ WATCH CONNECTED" : "○ OPEN WATCH APP")
                .font(.title3)
                .foregroundColor(wc.reachable ? .green : .orange)

            Text("\(elapsed)s")

            Text("Adjust with Watch")

            Text("If Watch can't detect all lens on your iPhone, restart both apps. This is Apple's fault and is not fixable from the code side")
        }

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
