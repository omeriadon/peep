//
//  VideoReceiver.swift
//  PeepWatch Watch App
//
//  Created by Adon Omeri on 25/1/2026.
//

import Combine
import UIKit
import WatchConnectivity


final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
	@Published var image: UIImage?
	@Published var lastTimestamp: TimeInterval?

	override init() {
		super.init()
		let s = WCSession.default
		s.delegate = self
		s.activate()
	}

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

	func sessionReachabilityDidChange(_ session: WCSession) {
		if !session.isReachable {
			DispatchQueue.main.async {
				self.image = nil
				self.lastTimestamp = nil
			}
		}
	}

	func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
		guard let type = message["type"] as? String else { return }

		DispatchQueue.main.async {
			if type == "frame" {
				if let data = message["data"] as? Data,
				   let img = UIImage(data: data),
				   let ts = message["ts"] as? TimeInterval {
					self.image = img
					self.lastTimestamp = ts
				}
			}

			if type == "goodbye" {
				self.image = nil
				self.lastTimestamp = message["ts"] as? TimeInterval
			}
		}
	}

	var isStale: Bool {
		guard let ts = lastTimestamp else { return true }
		return Date().timeIntervalSince1970 - ts > 1
	}
}

