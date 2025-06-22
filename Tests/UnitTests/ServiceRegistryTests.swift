import Testing
@testable import DTN7
import BP7
import Foundation

@Suite("Service Registry Tests")
struct ServiceRegistryTests {
    
    @Test("Register and retrieve services")
    func testServiceRegistration() async throws {
        let registry = ServiceRegistry()
        
        // Register services
        let echoService = DtnService(
            tag: 7,
            endpoint: try! EndpointID.from("dtn://node1/echo"),
            description: "Echo service"
        )
        let testService = DtnService(
            tag: 42,
            endpoint: try! EndpointID.from("dtn://node1/test"),
            description: "Test service"
        )
        
        await registry.register(echoService)
        await registry.register(testService)
        
        // Retrieve by tag
        let retrievedEcho = await registry.getService(tag: 7)
        #expect(retrievedEcho?.tag == 7)
        #expect(retrievedEcho?.description == "Echo service")
        
        let retrievedTest = await registry.getService(tag: 42)
        #expect(retrievedTest?.tag == 42)
        
        // Non-existent service
        let unknownService = await registry.getService(tag: 255)
        #expect(unknownService == nil)
    }
    
    @Test("Get all services")
    func testGetAllServices() async throws {
        let registry = ServiceRegistry()
        
        let service1 = DtnService(tag: 1, endpoint: try! EndpointID.from("dtn://node1/service1"), description: "Service 1")
        let service2 = DtnService(tag: 2, endpoint: try! EndpointID.from("dtn://node1/service2"), description: "Service 2")
        let service3 = DtnService(tag: 3, endpoint: try! EndpointID.from("dtn://node1/service3"), description: "Service 3")
        
        await registry.register(service1)
        await registry.register(service2)
        await registry.register(service3)
        
        let services = await registry.getAllServices()
        
        #expect(services.count == 3)
        #expect(services.contains(where: { $0.tag == 1 }))
        #expect(services.contains(where: { $0.tag == 2 }))
        #expect(services.contains(where: { $0.tag == 3 }))
    }
    
    @Test("Overwrite existing service")
    func testServiceOverwrite() async throws {
        let registry = ServiceRegistry()
        
        // Register initial service
        let initial = DtnService(tag: 10, endpoint: try! EndpointID.from("dtn://node1/initial"), description: "Initial")
        await registry.register(initial)
        #expect(await registry.getService(tag: 10)?.description == "Initial")
        
        // Overwrite with new service
        let updated = DtnService(tag: 10, endpoint: try! EndpointID.from("dtn://node1/updated"), description: "Updated")
        await registry.register(updated)
        #expect(await registry.getService(tag: 10)?.description == "Updated")
    }
    
    @Test("Unregister service")
    func testServiceUnregistration() async throws {
        let registry = ServiceRegistry()
        
        // Register and verify
        let service = DtnService(tag: 20, endpoint: try! EndpointID.from("dtn://node1/temp"), description: "Temp")
        await registry.register(service)
        #expect(await registry.getService(tag: 20) != nil)
        
        // Unregister
        await registry.unregister(tag: 20)
        #expect(await registry.getService(tag: 20) == nil)
    }
    
    @Test("Get services by endpoint")
    func testGetServicesByEndpoint() async throws {
        let registry = ServiceRegistry()
        let endpoint = try! EndpointID.from("dtn://node1/multi")
        
        // Register multiple services on same endpoint
        let service1 = DtnService(tag: 1, endpoint: endpoint, description: "Service 1")
        let service2 = DtnService(tag: 2, endpoint: endpoint, description: "Service 2")
        let service3 = DtnService(tag: 3, endpoint: try! EndpointID.from("dtn://node1/other"), description: "Service 3")
        
        await registry.register(service1)
        await registry.register(service2)
        await registry.register(service3)
        
        let allServices = await registry.getAllServices()
        let endpointServices = allServices.filter { $0.endpoint == endpoint }
        
        #expect(endpointServices.count == 2)
        #expect(endpointServices.contains(where: { $0.tag == 1 }))
        #expect(endpointServices.contains(where: { $0.tag == 2 }))
    }
}