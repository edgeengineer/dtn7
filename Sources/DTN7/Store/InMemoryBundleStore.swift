#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7

/// An in-memory implementation of the `BundleStore` protocol.
public actor InMemoryBundleStore: BundleStore {
    private var bundles: [String: BP7.Bundle] = [:]
    private var metadata: [String: BundlePack] = [:]

    public init() {}

    public func push(bundle: BP7.Bundle) throws {
        let bundlePack = BundlePack(from: bundle)
        if bundles[bundlePack.id] == nil {
            metadata[bundlePack.id] = bundlePack
        }
        bundles[bundlePack.id] = bundle
    }

    public func updateMetadata(bundlePack: BundlePack) throws {
        guard metadata[bundlePack.id] != nil else {
            throw BundleStoreError.bundleNotFound
        }
        metadata[bundlePack.id] = bundlePack
    }

    public func remove(bundleId: String) async throws {
        guard var meta = await getMetadata(bundleId: bundleId) else {
            throw BundleStoreError.bundleNotFound
        }
        meta.constraints.insert(.deleted)
        try updateMetadata(bundlePack: meta)
        
        guard bundles.removeValue(forKey: bundleId) != nil else {
            throw BundleStoreError.bundleNotFound
        }
    }

    public func count() -> UInt64 {
        return UInt64(bundles.count)
    }

    public func allIds() -> [String] {
        return Array(bundles.keys)
    }

    public func hasItem(bundleId: String) -> Bool {
        return bundles[bundleId] != nil
    }

    public func allBundles() -> [BundlePack] {
        return Array(metadata.values)
    }

    public func getBundle(bundleId: String) -> BP7.Bundle? {
        return bundles[bundleId]
    }

    public func getMetadata(bundleId: String) -> BundlePack? {
        return metadata[bundleId]
    }
}

public enum BundleStoreError: Error {
    case bundleNotFound
} 