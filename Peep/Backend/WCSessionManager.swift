//
//  CameraStreamer.swift
//  Peep
//
//  Created by Adon Omeri on 25/1/2026.
//

import Combine
import Foundation
import UIKit
import WatchConnectivity

final class WCSessionManager: NSObject, WCSessionDelegate {
	static let shared = WCSessionManager()
	override private init() { super.init() }

	func start() {
		guard WCSession.isSupported() else { return }
		let session = WCSession.default
		session.delegate = self
		session.activate()
		print("[iPhone] WCSession activated")
	}

	func sendFrame(_ jpegData: Data) {
		let sizeKB = jpegData.count / 1024
		print("[iPhone] Frame size:", sizeKB, "KB")

		guard jpegData.count <= 65000 else {
			print("[iPhone] Frame dropped (too large)")
			return
		}

		WCSession.default.sendMessage(
			["frame": jpegData],
			replyHandler: nil,
			errorHandler: { error in
				print("[iPhone] sendMessage error:", error)
			}
		)
	}

	// Required stubs
	func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}
	func sessionDidBecomeInactive(_: WCSession) {}
	func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
