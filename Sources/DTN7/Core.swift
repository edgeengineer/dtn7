import Foundation
import BP7

/// A DTN7 node ID, which is an alias for the `EndpointID` from the `bp7` library.
public typealias NodeID = EndpointID

/// A struct to hold statistics about the DTN daemon's operation.
public struct DtnStatistics: Sendable {
    public var incoming: UInt64 = 0
    public var dups: UInt64 = 0
    public var outgoing: UInt64 = 0
    public var delivered: UInt64 = 0
    public var failed: UInt64 = 0
    public var broken: UInt64 = 0
    public var stored: UInt64 = 0
    
    public init() {}
    
    public mutating func recordIncoming() {
        incoming += 1
    }
    
    public mutating func recordDuplicate() {
        dups += 1
    }
    
    public mutating func recordOutgoing() {
        outgoing += 1
    }
    
    public mutating func recordDelivered() {
        delivered += 1
    }
    
    public mutating func recordFailed() {
        failed += 1
    }
    
    public mutating func recordBroken() {
        broken += 1
    }
    
    public mutating func updateStored(_ count: UInt64) {
        stored = count
    }
}

/// Represents the type of a peer connection.
public enum PeerType: String, Codable, Equatable, Sendable {
    case `static`
    case dynamic
}

/// Represents the address of a peer.
public enum PeerAddress: Codable, Equatable, Hashable, Sendable {
    case ip(host: String, port: Int)
    case broadcastGeneric(domain: String, address: String)
    case generic(String)
}

/// Represents a DTN peer.
public struct DtnPeer: Codable, Equatable, Sendable {
    public let eid: EndpointID
    public let addr: PeerAddress
    public let conType: PeerType
    public let period: TimeInterval?
    public let claList: [(String, UInt16?)]
    public let services: [UInt8: String]
    public var lastContact: TimeInterval
    public var fails: UInt16
    
    public init(eid: EndpointID, addr: PeerAddress, conType: PeerType, period: TimeInterval?, claList: [(String, UInt16?)], services: [UInt8: String], lastContact: TimeInterval, fails: UInt16) {
        self.eid = eid
        self.addr = addr
        self.conType = conType
        self.period = period
        self.claList = claList
        self.services = services
        self.lastContact = lastContact
        self.fails = fails
    }

    // Manual Equatable conformance
    public static func == (lhs: DtnPeer, rhs: DtnPeer) -> Bool {
        return lhs.eid == rhs.eid &&
            lhs.addr == rhs.addr &&
            lhs.conType == rhs.conType &&
            lhs.period == rhs.period &&
            lhs.claList.count == rhs.claList.count && // Simplified check for tuples
            lhs.services == rhs.services &&
            lhs.lastContact == rhs.lastContact &&
            lhs.fails == rhs.fails
    }
    
    enum CodingKeys: String, CodingKey {
        case eid, addr, conType, period, claList, services, lastContact, fails
    }
    
    // Custom Codable conformance to handle claList tuple and EndpointID
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eidString = try container.decode(String.self, forKey: .eid)
        eid = try EndpointID.from(eidString)
        addr = try container.decode(PeerAddress.self, forKey: .addr)
        conType = try container.decode(PeerType.self, forKey: .conType)
        period = try container.decodeIfPresent(TimeInterval.self, forKey: .period)
        
        var claListContainer = try container.nestedUnkeyedContainer(forKey: .claList)
        var decodedClaList: [(String, UInt16?)] = []
        while !claListContainer.isAtEnd {
            var tupleContainer = try claListContainer.nestedUnkeyedContainer()
            let item1 = try tupleContainer.decode(String.self)
            let item2 = try tupleContainer.decode(UInt16?.self)
            decodedClaList.append((item1, item2))
        }
        claList = decodedClaList
        
        services = try container.decode([UInt8: String].self, forKey: .services)
        lastContact = try container.decode(TimeInterval.self, forKey: .lastContact)
        fails = try container.decode(UInt16.self, forKey: .fails)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eid.description, forKey: .eid)
        try container.encode(addr, forKey: .addr)
        try container.encode(conType, forKey: .conType)
        try container.encodeIfPresent(period, forKey: .period)

        var claListContainer = container.nestedUnkeyedContainer(forKey: .claList)
        for (item1, item2) in claList {
            var tupleContainer = claListContainer.nestedUnkeyedContainer()
            try tupleContainer.encode(item1)
            try tupleContainer.encode(item2)
        }
        
        try container.encode(services, forKey: .services)
        try container.encode(lastContact, forKey: .lastContact)
        try container.encode(fails, forKey: .fails)
    }
    
    /// Parse a peer from a string format like "mtcp://192.168.2.1:2342/node2"
    public static func from(_ peerString: String) -> DtnPeer? {
        // Parse format: <protocol>://<host>:<port>/<node_id>
        guard let url = URL(string: peerString),
              let host = url.host,
              let port = url.port,
              let scheme = url.scheme else {
            return nil
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard !pathComponents.isEmpty else {
            return nil
        }
        
        let nodeId = pathComponents.joined(separator: "/")
        guard let eid = try? EndpointID.from("dtn://\(nodeId)") else {
            return nil
        }
        
        return DtnPeer(
            eid: eid,
            addr: .ip(host: host, port: port),
            conType: .static,
            period: nil,
            claList: [(scheme, UInt16(port))],
            services: [:],
            lastContact: 0,
            fails: 0
        )
    }
} 