//
//  WatchSessionManager.swift
//  PeepWatch Watch App
//  Created by Adon Omeri on 25/1/2026.
//

import Combine
import UIKit
import WatchConnectivity

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var image: UIImage?
    @Published var lastTimestamp: TimeInterval?
    @Published var lenses: [LensDescriptor] = [LensDescriptor.default]

    var isStale: Bool {
        guard let ts = lastTimestamp else { return true }
        return Date().timeIntervalSince1970 - ts > 1
    }

    struct LensDescriptor: Identifiable, Equatable {
        let name: String
        let zoom: CGFloat
        let displayName: String

        var id: String { name }

        static var `default`: LensDescriptor {
            LensDescriptor(name: "wide", zoom: 1.0, displayName: "Wide (1.0x)")
        }
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

    func session(_: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
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
                self.lenses = [LensDescriptor.default]
            }
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case "frame":
                if let data = message["data"] as? Data,
                   let img = UIImage(data: data),
                   let ts = message["ts"] as? TimeInterval
                {
                    print("[WatchSession] Received frame:", data.count / 1024, "KB")
                    self.image = img
                    self.lastTimestamp = ts
                }
            case "goodbye":
                self.image = nil
                self.lastTimestamp = message["ts"] as? TimeInterval
            case "lensInfo":
                if let raw = message["lenses"] as? [[String: Any]] {
                    let parsed = raw.compactMap { dict -> LensDescriptor? in
                        guard let name = dict["name"] as? String,
                              let zoom = dict["zoom"] as? Double,
                              let display = dict["displayName"] as? String else { return nil }
                        return LensDescriptor(name: name, zoom: CGFloat(zoom), displayName: display)
                    }
                    self.lenses = parsed.isEmpty ? [LensDescriptor.default] : parsed.sorted(by: { $0.zoom < $1.zoom })
                }
            default:
                break
            }
        }
    }

    func requestLens(_ lens: String) {
        guard WCSession.default.isReachable else { return }
        let msg: [String: Any] = ["type": "requestLens", "lens": lens]
        WCSession.default.sendMessage(msg, replyHandler: nil) { error in
            print("[WatchSession] Lens request error:", error)
        }
    }
}
