//
//  MultipeerService.swift
//  InternationalDraughts
//
//  Nearby two-player match over MultipeerConnectivity (works without any
//  internet connection, via peer-to-peer Wi-Fi / Bluetooth).
//
//  Flow: host advertises a room and confirms incoming invitations; the joiner
//  browses via the system MCBrowserViewController and invites the host. Once
//  the MCSession connects, both sides exchange JSON `NetMessage`s.
//

import Foundation
import MultipeerConnectivity
import UIKit

/// Wire format for the match. One flat struct keeps the JSON trivial.
struct NetMessage: Codable {
    enum Kind: String, Codable {
        case move
        case restart
    }

    var kind: Kind
    var from: Int?
    var to: Int?
    var captures: [Int]?
    var path: [Int]?

    static func move(_ m: Move) -> NetMessage {
        NetMessage(kind: .move, from: m.from, to: m.to, captures: m.captures, path: m.path)
    }
}

final class MultipeerService: NSObject {

    /// Bonjour service type; must match NSBonjourServices in Info.plist.
    static let serviceType = "intl-draughts"

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var autoJoin = false
    private var invitedPeers: Set<MCPeerID> = []

    /// Test hook (-mpAutoHost): accept the first invitation without asking.
    var autoAcceptInvitations = false

    // Callbacks are always delivered on the main queue.
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?
    var onMessage: ((NetMessage) -> Void)?
    /// (peerName, respond) — call respond(true) to accept the invitation.
    var onInvitation: ((String, @escaping (Bool) -> Void) -> Void)?

    private(set) lazy var session: MCSession = {
        let s = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()

    var isConnected: Bool { !session.connectedPeers.isEmpty }
    var connectedPeerName: String? { session.connectedPeers.first?.displayName }

    // MARK: - Hosting (创建房间)

    func startHosting() {
        stopDiscovery()
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    // MARK: - Joining (搜索房间)

    /// System-provided nearby-peer picker for the manual join flow.
    func makeBrowserViewController() -> MCBrowserViewController {
        stopDiscovery()
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        self.browser = browser
        let vc = MCBrowserViewController(browser: browser, session: session)
        vc.maximumNumberOfPeers = 2
        return vc
    }

    /// Test hook (-mpAutoJoin): invite the first room found, no UI.
    func startAutoJoin() {
        stopDiscovery()
        autoJoin = true
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    // MARK: - Lifecycle

    /// Stop advertising/browsing; keeps an established session alive.
    func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        autoJoin = false
        invitedPeers.removeAll()
    }

    func disconnect() {
        stopDiscovery()
        session.disconnect()
    }

    // MARK: - Messaging

    func send(_ message: NetMessage) {
        guard !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.stopDiscovery()
                self.onPeerConnected?(peerID.displayName)
            case .notConnected:
                self.onPeerDisconnected?(peerID.displayName)
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            self.onMessage?(message)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate (host side)

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            if self.autoAcceptInvitations {
                invitationHandler(true, self.session)
                return
            }
            guard let onInvitation = self.onInvitation else {
                invitationHandler(false, nil)
                return
            }
            onInvitation(peerID.displayName) { accepted in
                invitationHandler(accepted, accepted ? self.session : nil)
            }
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (auto-join test hook)

extension MultipeerService: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        guard autoJoin, !invitedPeers.contains(peerID) else { return }
        invitedPeers.insert(peerID)
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        invitedPeers.remove(peerID)
    }
}
