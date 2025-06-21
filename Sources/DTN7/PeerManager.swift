import Foundation
import BP7
import AsyncAlgorithms

/// Events that can occur related to peers
public enum PeerEvent: Sendable {
    case discovered(DtnPeer)
    case updated(DtnPeer)
    case lost(DtnPeer)
    case connectionEstablished(DtnPeer, CLAConnection)
    case connectionLost(DtnPeer, CLAConnection)
}

/// Manages DTN peers and their lifecycle
public actor PeerManager {
    private var peers: [EndpointID: DtnPeer] = [:]
    private let peerTimeout: TimeInterval
    private var peerTimeoutTask: Task<Void, Never>?
    
    /// Channel for peer events
    public let peerEvents = AsyncChannel<PeerEvent>()
    
    public init(peerTimeout: TimeInterval = 300) {
        self.peerTimeout = peerTimeout
    }
    
    /// Start the peer manager
    public func start() {
        peerTimeoutTask = Task {
            await runPeerTimeoutCheck()
        }
    }
    
    /// Stop the peer manager
    public func stop() {
        peerTimeoutTask?.cancel()
        peerTimeoutTask = nil
    }
    
    /// Add or update a peer
    public func addOrUpdatePeer(_ peer: DtnPeer) async {
        let isNew = peers[peer.eid] == nil
        var updatedPeer = peer
        updatedPeer.lastContact = Date.now.timeIntervalSince1970
        updatedPeer.fails = 0
        
        peers[peer.eid] = updatedPeer
        
        if isNew {
            await peerEvents.send(.discovered(updatedPeer))
        } else {
            await peerEvents.send(.updated(updatedPeer))
        }
    }
    
    /// Remove a peer
    public func removePeer(_ eid: EndpointID) async {
        if let peer = peers.removeValue(forKey: eid) {
            await peerEvents.send(.lost(peer))
        }
    }
    
    /// Get a peer by endpoint ID
    public func getPeer(_ eid: EndpointID) -> DtnPeer? {
        peers[eid]
    }
    
    /// Get all known peers
    public func getAllPeers() -> [DtnPeer] {
        Array(peers.values)
    }
    
    /// Get peers that haven't been seen recently
    public func getStalePeers() -> [DtnPeer] {
        let cutoff = Date.now.timeIntervalSince1970 - peerTimeout
        return peers.values.filter { $0.lastContact < cutoff }
    }
    
    /// Record a failed contact attempt
    public func recordFailure(for eid: EndpointID) {
        if var peer = peers[eid] {
            peer.fails += 1
            peers[eid] = peer
        }
    }
    
    /// Record a successful contact
    public func recordSuccess(for eid: EndpointID) {
        if var peer = peers[eid] {
            peer.lastContact = Date.now.timeIntervalSince1970
            peer.fails = 0
            peers[eid] = peer
        }
    }
    
    /// Run periodic timeout check
    private func runPeerTimeoutCheck() async {
        while !Task.isCancelled {
            // Check for stale peers
            let stalePeers = getStalePeers()
            for peer in stalePeers {
                await removePeer(peer.eid)
            }
            
            // Sleep for a while before next check
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
        }
    }
}

// Make DtnPeer Hashable for use in Sets
extension DtnPeer: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(eid)
    }
}