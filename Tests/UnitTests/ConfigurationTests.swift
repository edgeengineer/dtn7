import Testing
@testable import DTN7
import BP7
import Foundation

@Suite("Configuration Tests")
struct ConfigurationTests {
    
    @Test("Default configuration values")
    func testDefaultConfig() {
        let config = DtnConfig()
        
        #expect(config.nodeId == "")
        #expect(config.webPort == 4242)
        #expect(config.janitorInterval == 10)
        #expect(config.workdir == ".")
        #expect(config.db == "mem")
        #expect(config.routing == "epidemic")
        #expect(config.endpoints.isEmpty)
        #expect(config.clas.isEmpty)
        #expect(config.statics.isEmpty)
    }
    
    @Test("Custom configuration")
    func testCustomConfig() {
        var config = DtnConfig()
        config.nodeId = "dtn://mynode"
        config.webPort = 8080
        config.db = "mem"
        config.routing = "flooding"
        config.endpoints = ["dtn://mynode/app1", "dtn://mynode/app2"]
        
        #expect(config.nodeId == "dtn://mynode")
        #expect(config.webPort == 8080)
        #expect(config.db == "mem")
        #expect(config.routing == "flooding")
        #expect(config.endpoints.count == 2)
    }
    
    @Test("CLA configuration")
    func testCLAConfig() {
        var config = DtnConfig()
        
        let tcpCLA = DtnConfig.CLAConfig(
            type: "tcp",
            settings: ["port": "4556", "bind": "0.0.0.0"]
        )
        
        let udpCLA = DtnConfig.CLAConfig(
            type: "udp",
            settings: ["port": "4557"]
        )
        
        config.clas = [tcpCLA, udpCLA]
        
        #expect(config.clas.count == 2)
        #expect(config.clas[0].type == "tcp")
        #expect(config.clas[0].settings["port"] == "4556")
        #expect(config.clas[1].type == "udp")
    }
    
    @Test("Static peer configuration")
    func testStaticPeerConfig() throws {
        var config = DtnConfig()
        
        let peer1 = DtnPeer(
            eid: try! EndpointID.from("dtn://peer1"),
            addr: PeerAddress.generic("tcp://192.168.1.100:4556"),
            conType: .static,
            period: nil,
            claList: [("tcp", 4556)],
            services: [7: "echo"],
            lastContact: 0,
            fails: 0
        )
        
        let peer2 = DtnPeer(
            eid: try! EndpointID.from("dtn://peer2"),
            addr: PeerAddress.generic("tcp://192.168.1.200:4556"),
            conType: .static,
            period: nil,
            claList: [("tcp", 4556)],
            services: [:],
            lastContact: 0,
            fails: 0
        )
        
        config.statics = [peer1, peer2]
        
        #expect(config.statics.count == 2)
        #expect(config.statics[0].eid.description == "dtn://peer1/")
        #expect(config.statics[0].services[7] == "echo")
    }
    
    @Test("Configuration JSON encoding/decoding")
    func testConfigurationCoding() throws {
        var config = DtnConfig()
        config.nodeId = "dtn://testnode"
        config.webPort = 5000
        config.endpoints = ["dtn://testnode/app"]
        config.clas = [
            DtnConfig.CLAConfig(type: "tcp", settings: ["port": "4556"])
        ]
        
        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(config)
        
        // Decode
        let decoder = JSONDecoder()
        let decodedConfig = try decoder.decode(DtnConfig.self, from: jsonData)
        
        #expect(decodedConfig.nodeId == config.nodeId)
        #expect(decodedConfig.webPort == config.webPort)
        #expect(decodedConfig.endpoints == config.endpoints)
        #expect(decodedConfig.clas.count == config.clas.count)
        #expect(decodedConfig.clas[0].type == "tcp")
    }
}