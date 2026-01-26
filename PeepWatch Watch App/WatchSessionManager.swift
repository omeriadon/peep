//
//  WatchSessionManager.swift
//  PeepWatch Watch App
//

import Combine
import UIKit
import WatchConnectivity

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
	static let shared = WatchSessionManager()
	
	@Published var image: UIImage?
	@Published var lastTimestamp: TimeInterval?
	
	var isStale: Bool {
		guard let ts = lastTimestamp else { return true }
		return Date().timeIntervalSince1970 - ts > 1
	}
	
	override init() {
		super.init()
		activateSession()
	}
	
	private func activateSession() {
		guard WCSession.isSupported() else { return }
		let session = WCSession.default
		session.delegate = self
		session.activate()
	}
	
	// MARK: - WCSessionDelegate
	
	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		if let err = error {
			print("[WatchSession] Activation error:", err)
		} else {
			print("[WatchSession] Activated with state:", activationState.rawValue)
		}
	}
	
	func sessionReachabilityDidChange(_ session: WCSession) {
		DispatchQueue.main.async {
			if !session.isReachable {
				self.image = nil
				self.lastTimestamp = nil
			}
		}
	}
	
	func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
		guard let type = message["type"] as? String else { return }
		
		DispatchQueue.main.async {
			switch type {
			case "frame":
				if let data = message["data"] as? Data,
				   let img = UIImage(data: data),
				   let ts = message["ts"] as? TimeInterval {
					print("[WatchSession] Received frame:", data.count / 1024, "KB")
					self.image = img
					self.lastTimestamp = ts
				}
			case "goodbye":
				self.image = nil
				self.lastTimestamp = message["ts"] as? TimeInterval
			default:
				break
			}
		}
	}
	
	// Optional: Send messages to iPhone (e.g., lens request)
	func requestLens(_ lens: String) {
		guard WCSession.default.isReachable else { return }
		let msg: [String: Any] = ["type": "requestLens", "lens": lens]
		WCSession.default.sendMessage(msg, replyHandler: nil) { error in
			print("[WatchSession] Lens request error:", error)
		}
	}
}
