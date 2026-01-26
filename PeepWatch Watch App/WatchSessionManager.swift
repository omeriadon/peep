//
//  VideoReceiver.swift
//  PeepWatch Watch App
//
//  Created by Adon Omeri on 25/1/2026.
//

import Combine
import AVFoundation
import WatchConnectivity
import UIKit

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
	@Published var image: UIImage?

	override init() {
		super.init()
		let session = WCSession.default
		session.delegate = self
		session.activate()
		print("[Watch] WCSession activated")
	}

	func session(
		_ session: WCSession,
		didReceiveMessage message: [String : Any]
	) {
		guard let data = message["frame"] as? Data else { return }
		print("[Watch] Received frame:", data.count / 1024, "KB")

		guard let img = UIImage(data: data) else {
			print("[Watch] Decode failed")
			return
		}

		DispatchQueue.main.async {
			self.image = img
		}
	}

	func session(
		_ session: WCSession,
		activationDidCompleteWith activationState: WCSessionActivationState,
		error: Error?
	) {}
}
