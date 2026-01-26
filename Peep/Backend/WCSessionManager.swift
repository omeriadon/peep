//
//  WCSessionManager.swift
//  Peep
//
//  Created by Adon Omeri on 25/1/2026.
//

import Combine
import UIKit
import WatchConnectivity

final class WCSessionManager: NSObject, WCSessionDelegate, ObservableObject {
	static let shared = WCSessionManager()

	@Published var reachable = false
	@Published var requestedLens: String?

	private var lensInfoPayload: [[String: Any]] = []

	private override init() {
		super.init()
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(appWillResignActive),
			name: UIApplication.willResignActiveNotification,
			object: nil
		)
	}

	func start() {
		guard WCSession.isSupported() else { return }
		let s = WCSession.default
		s.delegate = self
		s.activate()
	}

	@objc private func appWillResignActive() {
		sendGoodbye()
	}

	func sendFrame(_ data: Data, timestamp: TimeInterval) {
		guard WCSession.default.isReachable else { return }
		WCSession.default.sendMessage(
			["type": "frame", "data": data, "ts": timestamp],
			replyHandler: nil,
			errorHandler: nil
		)
	}

	func updateAvailableLensPayload(_ payload: [[String: Any]]) {
		lensInfoPayload = payload
		sendLensInfoMessage()
	}

	private func sendLensInfoMessage() {
		guard WCSession.default.isReachable, !lensInfoPayload.isEmpty else { return }
		WCSession.default.sendMessage([
			"type": "lensInfo",
			"lenses": lensInfoPayload
		], replyHandler: nil) { error in
			print("[WCSession] Lens info send error:", error)
		}
	}

	func sendGoodbye() {
		guard WCSession.default.isReachable else { return }
		WCSession.default.sendMessage(
			["type": "goodbye", "ts": Date().timeIntervalSince1970],
			replyHandler: nil,
			errorHandler: nil
		)
	}

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		reachable = session.isReachable
	}

	func sessionReachabilityDidChange(_ session: WCSession) {
		reachable = session.isReachable
		if session.isReachable {
			sendLensInfoMessage()
		}
	}

	func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
		guard let type = message["type"] as? String else { return }
		
		DispatchQueue.main.async {
			switch type {
			case "requestLens":
				if let lens = message["lens"] as? String {
					self.requestedLens = lens
				}
			default:
				break
			}
		}
	}

	func sessionDidBecomeInactive(_ session: WCSession) {}
	func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
