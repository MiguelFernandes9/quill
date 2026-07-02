import Foundation
import UIKit
import MultipeerConnectivity

protocol MultipeerSessionDelegate: AnyObject {
    func multipeer(_ session: MultipeerSession, didReceive data: Data, from peer: MCPeerID)
    func multipeer(_ session: MultipeerSession, peersChanged connected: [MCPeerID])
}

/// Thin MultipeerConnectivity transport: advertise, browse, auto-connect, and
/// move raw `Data` between peers. Knows nothing about sketches or messages —
/// that lives in `ConnectivityManager`.
final class MultipeerSession: NSObject {

    /// 1–15 chars, lowercase/digits/hyphen. Must match the Bonjour service in
    /// Info.plist (`_quill-canvas._tcp` / `._udp`).
    static let serviceType = "quill-canvas"

    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    weak var delegate: MultipeerSessionDelegate?

    var connectedPeers: [MCPeerID] { session.connectedPeers }

    override init() {
        // Advertise the PLATFORM KIND, not UIDevice.current.name — iOS 16+
        // returns the generic model ("iPad") for privacy, and Catalyst's value
        // is unreliable, which made both peers read as "iPad". A per-launch
        // suffix guarantees distinct display names so the invite tie-break
        // below always resolves.
        #if targetEnvironment(macCatalyst)
        let kind = "Mac"
        #else
        let kind = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
        let suffix = String(UUID().uuidString.prefix(4))
        let name = "\(kind)-\(suffix)"
        myPeerID = MCPeerID(displayName: String(name.prefix(63)))
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    /// Once connected, keep the radios quiet (2-device app — nobody else to
    /// find); resume scanning when the peer drops.
    private func updateDiscovery(connected: Bool) {
        if connected {
            advertiser.stopAdvertisingPeer()
            browser.stopBrowsingForPeers()
        } else {
            advertiser.startAdvertisingPeer()
            browser.startBrowsingForPeers()
        }
    }

    func send(_ data: Data, reliable: Bool) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        try? session.send(data, toPeers: peers, with: reliable ? .reliable : .unreliable)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peers = session.connectedPeers
        updateDiscovery(connected: !peers.isEmpty)
        DispatchQueue.main.async { self.delegate?.multipeer(self, peersChanged: peers) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.delegate?.multipeer(self, didReceive: data, from: peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser (auto-accept invitations)

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

// MARK: - Browser (auto-invite, deterministic tie-break)

extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        // Only the lexicographically-smaller peer invites, so both sides don't
        // invite each other simultaneously (invitation glare).
        if myPeerID.displayName < peerID.displayName {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
