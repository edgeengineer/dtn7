import Foundation
import BP7
import CSQLite

/// Wrapper to make OpaquePointer Sendable
private struct SendableDB: @unchecked Sendable {
    let pointer: OpaquePointer
}

/// A persistent bundle store implementation using SQLite.
public final class CSQLiteStore: BundleStore, @unchecked Sendable {
    private let db: OpaquePointer
    private let path: String
    private let queue = DispatchQueue(label: "csqlite.store.queue")
    
    /// Error types specific to CSQLiteStore
    public enum CSQLiteStoreError: Error {
        case databaseError(String)
        case notFound
        case constraintViolation
        case invalidData
    }
    
    /// Initialize a new CSQLiteStore with the given database path
    public init(path: String) throws {
        self.path = path
        
        var result = CSQLiteResult(rawValue: 0)
        guard let database = csqlite_open(path, &result),
              result == CSQLITE_OK else {
            throw CSQLiteStoreError.databaseError("Failed to open database at \(path)")
        }
        
        self.db = database
    }
    
    deinit {
        csqlite_close(db)
    }
    
    // MARK: - BundleStore Protocol Implementation
    
    public func push(bundle: BP7.Bundle) async throws {
        let metadata = BundlePack(from: bundle)
        let bundleId = metadata.id
        let bundleData = bundle.encode()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                bundleId.withCString { idCStr in
                    metadata.source.description.withCString { sourceCStr in
                        metadata.destination.description.withCString { destCStr in
                            bundleData.withUnsafeBytes { dataBytes in
                                var cMetadata = CSQLiteBundleMetadata(
                                    id: idCStr,
                                    source: sourceCStr,
                                    destination: destCStr,
                                    creation_time: metadata.creationTime,
                                    size: metadata.size,
                                    constraints: Int32(metadata.constraints.rawValue)
                                )
                                
                                let result = csqlite_store_bundle(
                                    self.db,
                                    idCStr,
                                    dataBytes.bindMemory(to: UInt8.self).baseAddress,
                                    bundleData.count,
                                    &cMetadata
                                )
                                
                                switch result {
                                case CSQLITE_OK:
                                    continuation.resume()
                                case CSQLITE_CONSTRAINT:
                                    continuation.resume(throwing: CSQLiteStoreError.constraintViolation)
                                default:
                                    continuation.resume(throwing: CSQLiteStoreError.databaseError("Failed to store bundle"))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func updateMetadata(bundlePack: BundlePack) async throws {
        // Prepare strings outside of nested closures
        let idCopy = bundlePack.id
        let sourceCopy = bundlePack.source.description
        let destCopy = bundlePack.destination.description
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            idCopy.withCString { idCStr in
                sourceCopy.withCString { sourceCStr in
                    destCopy.withCString { destCStr in
                        var cMetadata = CSQLiteBundleMetadata(
                            id: idCStr,
                            source: sourceCStr,
                            destination: destCStr,
                            creation_time: bundlePack.creationTime,
                            size: bundlePack.size,
                            constraints: Int32(bundlePack.constraints.rawValue)
                        )
                        
                        let result = csqlite_update_metadata(
                            db,
                            &cMetadata
                        )
                        
                        switch result {
                        case CSQLITE_OK:
                            continuation.resume()
                        case CSQLITE_NOT_FOUND:
                            continuation.resume(throwing: CSQLiteStoreError.notFound)
                        default:
                            continuation.resume(throwing: CSQLiteStoreError.databaseError("Failed to update metadata"))
                        }
                    }
                }
            }
        }
    }
    
    public func remove(bundleId: String) async throws {
        let idCopy = bundleId
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            idCopy.withCString { idCStr in
                let result = csqlite_remove_bundle(
                    db,
                    idCStr
                )
                
                switch result {
                case CSQLITE_OK:
                    continuation.resume()
                case CSQLITE_NOT_FOUND:
                    continuation.resume(throwing: CSQLiteStoreError.notFound)
                default:
                    continuation.resume(throwing: CSQLiteStoreError.databaseError("Failed to remove bundle"))
                }
            }
        }
    }
    
    public func count() async -> UInt64 {
        return await withCheckedContinuation { continuation in
            queue.async {
                let count = csqlite_count_bundles(self.db)
                continuation.resume(returning: count)
            }
        }
    }
    
    public func allIds() async -> [String] {
        var ids: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var count: Int = 0
        
        let result = csqlite_get_all_ids(
            db,
            &ids,
            &count
        )
        
        guard result == CSQLITE_OK, let idsPtr = ids else {
            return []
        }
        
        var swiftIds: [String] = []
        for i in 0..<count {
            if let cStr = idsPtr[i] {
                swiftIds.append(String(cString: cStr))
            }
        }
        
        csqlite_free_ids(ids, count)
        return swiftIds
    }
    
    public func hasItem(bundleId: String) async -> Bool {
        let idCopy = bundleId
        
        return await withCheckedContinuation { continuation in
            idCopy.withCString { idCStr in
                var exists: Bool = false
                let result = csqlite_has_bundle(
                    db,
                    idCStr,
                    &exists
                )
                
                continuation.resume(returning: result == CSQLITE_OK && exists)
            }
        }
    }
    
    public func allBundles() async -> [BundlePack] {
        var metadataPtr: UnsafeMutablePointer<CSQLiteBundleMetadata>?
        var count: Int = 0
        
        let result = csqlite_get_all_metadata(
            db,
            &metadataPtr,
            &count
        )
        
        guard result == CSQLITE_OK, let metadata = metadataPtr else {
            return []
        }
        
        var bundlePacks: [BundlePack] = []
        
        for i in 0..<count {
            let meta = metadata[i]
            
            // Create BundlePack from C metadata
            if let id = meta.id,
               let source = meta.source,
               let destination = meta.destination,
               let sourceEid = try? EndpointID.from(String(cString: source)),
               let destEid = try? EndpointID.from(String(cString: destination)) {
                
                var pack = BundlePack(
                    id: String(cString: id),
                    source: sourceEid,
                    destination: destEid,
                    creationTime: meta.creation_time,
                    size: meta.size
                )
                pack.constraints = Constraints(rawValue: Int(meta.constraints))
                bundlePacks.append(pack)
            }
        }
        
        csqlite_free_metadata_array(metadata, count)
        return bundlePacks
    }
    
    public func getBundle(bundleId: String) async -> BP7.Bundle? {
        let idCopy = bundleId
        
        return try? await withCheckedThrowingContinuation { continuation in
            idCopy.withCString { idCStr in
                var bundleData: UnsafeMutablePointer<UInt8>?
                var bundleSize: Int = 0
                
                let result = csqlite_get_bundle(
                    db,
                    idCStr,
                    &bundleData,
                    &bundleSize
                )
                
                guard result == CSQLITE_OK,
                      let dataPtr = bundleData,
                      bundleSize > 0 else {
                    continuation.resume(throwing: CSQLiteStoreError.notFound)
                    return
                }
                
                let data = Data(bytes: dataPtr, count: bundleSize)
                csqlite_free_data(bundleData)
                
                do {
                    // Convert Data to [UInt8] array for BP7 Bundle decoding
                    let bytes = Array(data)
                    let bundle = try BP7.Bundle.decode(from: bytes)
                    continuation.resume(returning: bundle)
                } catch {
                    continuation.resume(throwing: CSQLiteStoreError.invalidData)
                }
            }
        }
    }
    
    public func getMetadata(bundleId: String) async -> BundlePack? {
        let idCopy = bundleId
        
        return try? await withCheckedThrowingContinuation { continuation in
            idCopy.withCString { idCStr in
                var cMetadata = CSQLiteBundleMetadata()
                
                let result = csqlite_get_metadata(
                    db,
                    idCStr,
                    &cMetadata
                )
                
                guard result == CSQLITE_OK,
                      let id = cMetadata.id,
                      let source = cMetadata.source,
                      let destination = cMetadata.destination else {
                    continuation.resume(throwing: CSQLiteStoreError.notFound)
                    return
                }
                
                do {
                    let sourceEid = try EndpointID.from(String(cString: source))
                    let destEid = try EndpointID.from(String(cString: destination))
                    
                    var pack = BundlePack(
                        id: String(cString: id),
                        source: sourceEid,
                        destination: destEid,
                        creationTime: cMetadata.creation_time,
                        size: cMetadata.size
                    )
                    pack.constraints = Constraints(rawValue: Int(cMetadata.constraints))
                    
                    // Free the allocated strings
                    csqlite_free_data(UnsafeMutableRawPointer(mutating: cMetadata.id))
                    csqlite_free_data(UnsafeMutableRawPointer(mutating: cMetadata.source))
                    csqlite_free_data(UnsafeMutableRawPointer(mutating: cMetadata.destination))
                    
                    continuation.resume(returning: pack)
                } catch {
                    continuation.resume(throwing: CSQLiteStoreError.invalidData)
                }
            }
        }
    }
}

// MARK: - BundlePack Extension

extension BundlePack {
    /// Initialize BundlePack with explicit values (needed for CSQLiteStore)
    init(id: String, source: EndpointID, destination: EndpointID, creationTime: UInt64, size: UInt64) {
        self.id = id
        self.source = source
        self.destination = destination
        self.creationTime = creationTime
        self.size = size
        self.constraints = []
    }
}

