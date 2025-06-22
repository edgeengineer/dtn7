#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7

/// A protocol that defines the interface for a bundle store.
public protocol BundleStore: Sendable {
    /// Adds a bundle to the store.
    func push(bundle: BP7.Bundle) async throws
    
    /// Updates the metadata of a bundle in the store.
    func updateMetadata(bundlePack: BundlePack) async throws

    /// Removes a bundle from the store.
    func remove(bundleId: String) async throws

    /// Returns the number of bundles in the store.
    func count() async -> UInt64

    /// Returns all bundle IDs in the store.
    func allIds() async -> [String]

    /// Checks if a bundle is in the store.
    func hasItem(bundleId: String) async -> Bool

    /// Returns all bundles in the store.
    func allBundles() async -> [BundlePack]

    /// Returns a bundle from the store.
    func getBundle(bundleId: String) async -> BP7.Bundle?

    /// Returns the metadata of a bundle from the store.
    func getMetadata(bundleId: String) async -> BundlePack?
}

/// A struct to hold metadata about a bundle.
public struct BundlePack: Codable, Equatable, Sendable {
    public let id: String
    public let source: EndpointID
    public let destination: EndpointID
    public let creationTime: UInt64
    public let size: UInt64
    // In the Rust code, constraints are a bitfield. We'll use an OptionSet for a more Swift-idiomatic approach.
    public var constraints: Constraints = []

    public init(from bundle: BP7.Bundle) {
        // Generate a unique ID based on source, timestamp, and sequence number
        let timestamp = bundle.primary.creationTimestamp.getDtnTime()
        let sequenceNumber = bundle.primary.creationTimestamp.getSequenceNumber()
        self.id = "\(bundle.primary.source)-\(timestamp)-\(sequenceNumber)"
        self.source = bundle.primary.source
        self.destination = bundle.primary.destination
        self.creationTime = timestamp
        self.size = UInt64(bundle.encode().count)
    }

    enum CodingKeys: String, CodingKey {
        case id, source, destination, creationTime, size, constraints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let sourceString = try container.decode(String.self, forKey: .source)
        source = try EndpointID.from(sourceString)
        let destString = try container.decode(String.self, forKey: .destination)
        destination = try EndpointID.from(destString)
        creationTime = try container.decode(UInt64.self, forKey: .creationTime)
        size = try container.decode(UInt64.self, forKey: .size)
        constraints = try container.decode(Constraints.self, forKey: .constraints)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source.description, forKey: .source)
        try container.encode(destination.description, forKey: .destination)
        try container.encode(creationTime, forKey: .creationTime)
        try container.encode(size, forKey: .size)
        try container.encode(constraints, forKey: .constraints)
    }
}

/// Represents the constraints on a bundle, such as whether it's pending forwarding or has been deleted.
public struct Constraints: OptionSet, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let dispatchPending = Constraints(rawValue: 1 << 0)
    public static let forwardPending = Constraints(rawValue: 1 << 1)
    public static let reassemblyPending = Constraints(rawValue: 1 << 2)
    public static let contraindicated = Constraints(rawValue: 1 << 3)
    public static let deleted = Constraints(rawValue: 1 << 4)
} 