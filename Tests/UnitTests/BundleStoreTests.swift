import Testing
@testable import DTN7
@testable import BP7
import Foundation

@Suite("Bundle Store Tests")
struct BundleStoreTests {
    
    @Test("InMemory store basic operations")
    func testInMemoryStore() async throws {
        let store = InMemoryBundleStore()
        
        // Create test bundle
        let bundle = createTestBundle(id: "test-1")
        let bundleId = BundlePack(from: bundle).id
        
        // Store bundle
        try await store.push(bundle: bundle)
        
        // Check if bundle exists
        let hasBundle = await store.hasItem(bundleId: bundleId)
        #expect(hasBundle == true)
        
        // Get bundle
        let retrieved = await store.getBundle(bundleId: bundleId)
        #expect(retrieved != nil)
        
        // Count bundles
        let count = await store.count()
        #expect(count == 1)
        
        // Remove bundle
        try await store.remove(bundleId: bundleId)
        let hasAfterRemove = await store.hasItem(bundleId: bundleId)
        #expect(hasAfterRemove == false)
    }
    
    @Test("Store multiple bundles")
    func testMultipleBundles() async throws {
        let store = InMemoryBundleStore()
        
        var bundleIds: [String] = []
        
        // Store multiple bundles
        for i in 1...5 {
            let bundle = createTestBundle(id: "test-\(i)")
            let bundleId = BundlePack(from: bundle).id
            bundleIds.append(bundleId)
            try await store.push(bundle: bundle)
        }
        
        let count = await store.count()
        #expect(count == 5)
        
        // Get all bundle IDs
        let allIds = await store.allIds()
        #expect(allIds.count == 5)
        
        // Remove specific bundle
        if bundleIds.count > 2 {
            try await store.remove(bundleId: bundleIds[2])
            let newCount = await store.count()
            #expect(newCount == 4)
        }
    }
    
    @Test("Get metadata")
    func testGetMetadata() async throws {
        let store = InMemoryBundleStore()
        
        // Store a bundle
        let bundle = createTestBundle(id: "test-meta")
        let bundleId = BundlePack(from: bundle).id
        
        try await store.push(bundle: bundle)
        
        // Get metadata
        let metadata = await store.getMetadata(bundleId: bundleId)
        #expect(metadata != nil)
        #expect(metadata?.id == bundleId)
    }
    
    @Test("Bundles by destination")
    func testBundlesByDestination() async throws {
        let store = InMemoryBundleStore()
        
        // Store bundles for different endpoints
        let bundle1 = createTestBundle(id: "b1", destination: "dtn://node1/app")
        let bundle2 = createTestBundle(id: "b2", destination: "dtn://node1/app")
        let bundle3 = createTestBundle(id: "b3", destination: "dtn://node2/app")
        
        try await store.push(bundle: bundle1)
        try await store.push(bundle: bundle2)
        try await store.push(bundle: bundle3)
        
        // Get bundles for specific destination
        let node1Dest = try! EndpointID.from("dtn://node1/app")
        let bundlePacks = await store.allBundles()
        let node1Bundles = bundlePacks.filter { pack in
            pack.destination == node1Dest
        }
        
        #expect(node1Bundles.count == 2)
    }
    
    // Helper function
    private func createTestBundle(id: String, destination: String = "dtn://dest/test") -> BP7.Bundle {
        // Create a simple bundle for testing
        let primary = PrimaryBlock(
            bundleControlFlags: BundleControlFlags(),
            destination: try! EndpointID.from(destination),
            source: try! EndpointID.from("dtn://source/test"),
            reportTo: try! EndpointID.from("dtn://source/test"),
            creationTimestamp: CreationTimestamp(time: 0, sequenceNumber: UInt64(abs(id.hashValue))),
            lifetime: 3600000
        )
        
        let bundle = BP7.Bundle(primary: primary, canonicals: [])
        return bundle
    }
}