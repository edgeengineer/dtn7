import Testing
@testable import DTN7
import BP7
import Foundation

@Suite("EndpointID Tests")
struct EndpointIDTests {
    
    @Test("Parse DTN scheme endpoint IDs")
    func testDTNEndpointParsing() throws {
        let eid = try EndpointID.from("dtn://node1/test")
        #expect(eid.description == "dtn://node1/test")
    }
    
    @Test("Parse IPN scheme endpoint IDs")
    func testIPNEndpointParsing() throws {
        let eid = try EndpointID.from("ipn:1.42")
        #expect(eid.description == "ipn:1.42")
    }
    
    @Test("Null endpoint ID")
    func testNullEndpoint() throws {
        let eid = try EndpointID.from("dtn:none")
        #expect(eid.description == "dtn:none")
    }
    
    @Test("Invalid endpoint IDs throw errors")
    func testInvalidEndpoints() {
        #expect(throws: Error.self) {
            _ = try EndpointID.from("invalid-scheme://test")
        }
        
        #expect(throws: Error.self) {
            _ = try EndpointID.from("")
        }
    }
    
    @Test("Endpoint ID equality")
    func testEndpointEquality() throws {
        let eid1 = try EndpointID.from("dtn://node1/test")
        let eid2 = try EndpointID.from("dtn://node1/test")
        let eid3 = try EndpointID.from("dtn://node2/test")
        
        #expect(eid1 == eid2)
        #expect(eid1 != eid3)
    }
    
    @Test("Endpoint ID string representation")
    func testEndpointStringRepresentation() throws {
        let eid1 = try EndpointID.from("dtn://node1/app/service")
        let eid2 = try EndpointID.from("ipn:42.1")
        
        #expect(eid1.description == "dtn://node1/app/service")
        #expect(eid2.description == "ipn:42.1")
    }
}