import Foundation
import Network
import BP7
import AsyncAlgorithms
import Logging

/// TCP Convergence Layer Agent implementing TCPCLv4 protocol
public actor TCPCLA: ConvergenceLayerAgent {
    public let id: String
    public let name: String = "tcp"
    public let incomingBundles = AsyncChannel<(BP7.Bundle, CLAConnection)>()
    
    private let config: TCPCLAConfig
    private var listener: NWListener?
    private var connections: [String: TCPConnection] = [:]
    private let logger = Logger(label: "TCPCLA")
    private var isRunning = false
    private var nodeId: String = "dtn://localhost"
    
    /// Configuration for TCP CLA
    public struct TCPCLAConfig: Sendable {
        public let port: UInt16
        public let bindAddress: String
        public let refuseExistingBundles: Bool
        public let keepaliveInterval: TimeInterval
        public let segmentMRU: UInt64
        public let transferMRU: UInt64
        
        public init(
            port: UInt16 = 4556,
            bindAddress: String = "0.0.0.0",
            refuseExistingBundles: Bool = false,
            keepaliveInterval: TimeInterval = 30,
            segmentMRU: UInt64 = 64000,
            transferMRU: UInt64 = 64000
        ) {
            self.port = port
            self.bindAddress = bindAddress
            self.refuseExistingBundles = refuseExistingBundles
            self.keepaliveInterval = keepaliveInterval
            self.segmentMRU = segmentMRU
            self.transferMRU = transferMRU
        }
    }
    
    public init(config: TCPCLAConfig = TCPCLAConfig(), nodeId: String? = nil) {
        self.id = "tcp-\(config.port)"
        self.config = config
        if let nodeId = nodeId {
            self.nodeId = nodeId
        }
    }
    
    /// Set the node ID for this CLA
    public func setNodeId(_ nodeId: String) {
        self.nodeId = nodeId
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        // Configure listener endpoint
        if config.bindAddress == "0.0.0.0" || config.bindAddress == "::" {
            _ = NWEndpoint.hostPort(host: .ipv4(.any), port: .init(integerLiteral: config.port))
        } else {
            _ = NWEndpoint.hostPort(host: .init(config.bindAddress), port: .init(integerLiteral: config.port))
        }
        
        listener = try NWListener(using: parameters, on: .init(integerLiteral: config.port))
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleIncomingConnection(connection)
            }
        }
        
        listener?.start(queue: .global())
        isRunning = true
        logger.info("TCP CLA started on port \(config.port)")
    }
    
    public func stop() async throws {
        guard isRunning else { return }
        
        listener?.cancel()
        listener = nil
        
        // Close all connections
        for connection in connections.values {
            await connection.close()
        }
        connections.removeAll()
        
        isRunning = false
        logger.info("TCP CLA stopped")
    }
    
    public func sendBundle(_ bundle: BP7.Bundle, to peer: DtnPeer) async throws {
        guard let peerAddress = extractTCPAddress(from: peer) else {
            throw CLAError.invalidPeerAddress
        }
        
        let connectionId = "\(peerAddress.host):\(peerAddress.port)"
        
        // Check if we have an existing connection
        if let connection = connections[connectionId], await connection.isActive {
            try await connection.sendBundle(bundle)
        } else {
            // Create new connection
            let connection = TCPConnection(
                config: config,
                remoteHost: peerAddress.host,
                remotePort: peerAddress.port,
                nodeId: peer.eid,
                incomingBundles: incomingBundles
            )
            
            connections[connectionId] = connection
            try await connection.connect()
            try await connection.sendBundle(bundle)
        }
    }
    
    public nonisolated func canReach(_ peer: DtnPeer) -> Bool {
        // Check if peer has TCP in its CLA list
        return peer.claList.contains { $0.0 == "tcp" || $0.0 == "mtcp" }
    }
    
    public func getConnections() async -> [CLAConnection] {
        var result: [CLAConnection] = []
        for connection in connections.values {
            if await connection.isActive {
                result.append(await connection.getConnectionInfo())
            }
        }
        return result
    }
    
    private func handleIncomingConnection(_ nwConnection: NWConnection) async {
        let connection = TCPConnection(
            config: config,
            nwConnection: nwConnection,
            incomingBundles: incomingBundles
        )
        
        let connectionId = connection.id
        connections[connectionId] = connection
        
        do {
            try await connection.acceptIncoming()
        } catch {
            logger.error("Failed to accept incoming connection: \(error)")
            connections.removeValue(forKey: connectionId)
        }
    }
    
    private func extractTCPAddress(from peer: DtnPeer) -> (host: String, port: UInt16)? {
        switch peer.addr {
        case .ip(let host, let port):
            return (host, UInt16(port))
        default:
            // Try to extract from CLA list
            for (cla, port) in peer.claList where cla == "tcp" || cla == "mtcp" {
                if let port = port, case .ip(let host, _) = peer.addr {
                    return (host, port)
                }
            }
            return nil
        }
    }
}

/// TCPCLv4 protocol implementation
actor TCPConnection {
    private let config: TCPCLA.TCPCLAConfig
    private let nwConnection: NWConnection
    private let incomingBundles: AsyncChannel<(BP7.Bundle, CLAConnection)>
    private let logger = Logger(label: "TCPConnection")
    
    let id: String
    var nodeId: EndpointID?
    var isActive: Bool = false
    private var keepaliveTask: Task<Void, Never>?
    
    init(config: TCPCLA.TCPCLAConfig, nwConnection: NWConnection, incomingBundles: AsyncChannel<(BP7.Bundle, CLAConnection)>) {
        self.config = config
        self.nwConnection = nwConnection
        self.incomingBundles = incomingBundles
        self.id = "\(nwConnection.endpoint)"
    }
    
    init(config: TCPCLA.TCPCLAConfig, remoteHost: String, remotePort: UInt16, nodeId: EndpointID, incomingBundles: AsyncChannel<(BP7.Bundle, CLAConnection)>) {
        self.config = config
        self.nodeId = nodeId
        self.incomingBundles = incomingBundles
        self.id = "\(remoteHost):\(remotePort)"
        
        let endpoint = NWEndpoint.hostPort(host: .init(remoteHost), port: .init(integerLiteral: remotePort))
        self.nwConnection = NWConnection(to: endpoint, using: .tcp)
    }
    
    func connect() async throws {
        nwConnection.start(queue: .global())
        
        // Wait for connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nwConnection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: CLAError.connectionCancelled)
                default:
                    break
                }
            }
        }
        
        // Send contact header
        try await sendContactHeader()
        // Receive contact header
        try await receiveContactHeader()
        // Exchange session init
        try await sendSessionInit()
        try await receiveSessionInit()
        
        isActive = true
        startKeepalive()
        startReceiving()
    }
    
    func acceptIncoming() async throws {
        nwConnection.start(queue: .global())
        
        // Receive contact header
        try await receiveContactHeader()
        // Send contact header
        try await sendContactHeader()
        // Exchange session init
        try await receiveSessionInit()
        try await sendSessionInit()
        
        isActive = true
        startKeepalive()
        startReceiving()
    }
    
    func sendBundle(_ bundle: BP7.Bundle) async throws {
        guard isActive else {
            throw CLAError.connectionNotActive
        }
        
        let bundleData = bundle.encode()
        let bundleId = BundlePack(from: bundle).id
        
        // Send transfer segment
        let message = TCPCLMessage.xferSegment(
            flags: 0x01, // START flag
            transferId: 1,
            extensionItems: [
                TCPCLExtension.transferLength(UInt64(bundleData.count))
            ],
            data: Data(bundleData)
        )
        
        try await send(message)
        logger.debug("Sent bundle \(bundleId) via TCP")
    }
    
    func close() async {
        keepaliveTask?.cancel()
        
        if isActive {
            // Send session termination
            let message = TCPCLMessage.sessTerm(
                flags: 0,
                reasonCode: 0x00 // Unknown reason
            )
            try? await send(message)
        }
        
        nwConnection.cancel()
        isActive = false
    }
    
    func getConnectionInfo() -> CLAConnection {
        CLAConnection(
            id: id,
            remoteEndpointId: nodeId,
            remoteAddress: "\(nwConnection.endpoint)",
            claType: "tcp",
            establishedAt: Date()
        )
    }
    
    private func sendContactHeader() async throws {
        let header = Data([
            0x64, 0x74, 0x6E, 0x21, // "dtn!"
            0x04, // Version 4
            0x00  // Flags
        ])
        
        try await sendData(header)
    }
    
    private func receiveContactHeader() async throws {
        let header = try await receiveData(count: 6)
        
        // Verify magic
        guard header[0...3] == Data([0x64, 0x74, 0x6E, 0x21]) else {
            throw CLAError.invalidProtocol("Invalid contact header magic")
        }
        
        // Verify version
        guard header[4] == 0x04 else {
            throw CLAError.unsupportedVersion(Int(header[4]))
        }
    }
    
    private func sendSessionInit() async throws {
        let nodeIdData = (nodeId?.description ?? "dtn://unknown").data(using: .utf8)!
        
        let message = TCPCLMessage.sessInit(
            keepalive: UInt16(config.keepaliveInterval),
            segmentMRU: config.segmentMRU,
            transferMRU: config.transferMRU,
            nodeId: nodeIdData,
            sessionExtensionItems: []
        )
        
        try await send(message)
    }
    
    private func receiveSessionInit() async throws {
        let message = try await receive()
        
        guard case .sessInit(_, _, _, let nodeIdData, _) = message else {
            throw CLAError.invalidProtocol("Expected SESS_INIT message")
        }
        
        if let nodeIdString = String(data: nodeIdData, encoding: .utf8) {
            nodeId = try? EndpointID.from(nodeIdString)
        }
    }
    
    private func startKeepalive() {
        keepaliveTask = Task {
            while !Task.isCancelled && isActive {
                try? await Task.sleep(nanoseconds: UInt64(config.keepaliveInterval * 1_000_000_000))
                
                if isActive {
                    let message = TCPCLMessage.keepalive
                    try? await send(message)
                }
            }
        }
    }
    
    private func startReceiving() {
        Task {
            while isActive {
                do {
                    let message = try await receive()
                    try await handleMessage(message)
                } catch {
                    logger.error("Error receiving message: \(error)")
                    await close()
                    break
                }
            }
        }
    }
    
    private func handleMessage(_ message: TCPCLMessage) async throws {
        switch message {
        case .xferSegment(let flags, _, _, let data):
            if flags & 0x01 != 0 { // START flag
                // This is a complete bundle
                if let bundle = try? BP7.Bundle.decode(from: Array(data)) {
                    let connection = getConnectionInfo()
                    await incomingBundles.send((bundle, connection))
                    
                    // Send acknowledgment
                    let ack = TCPCLMessage.xferAck(flags: 0, transferId: 1, length: UInt64(data.count))
                    try await send(ack)
                }
            }
            
        case .xferAck:
            // Bundle acknowledged
            break
            
        case .xferRefuse:
            logger.warning("Bundle transfer refused")
            
        case .keepalive:
            // Keepalive received
            break
            
        case .sessTerm:
            await close()
            
        case .msgReject:
            logger.error("Message rejected by peer")
            
        default:
            break
        }
    }
    
    private func send(_ message: TCPCLMessage) async throws {
        let data = message.encode()
        try await sendData(data)
    }
    
    private func receive() async throws -> TCPCLMessage {
        // Read message type
        let typeData = try await receiveData(count: 1)
        let messageType = typeData[0]
        
        // Read message based on type
        switch messageType {
        case 0x01: // XFER_SEGMENT
            return try await receiveXferSegment()
        case 0x02: // XFER_ACK
            return try await receiveXferAck()
        case 0x03: // XFER_REFUSE
            return try await receiveXferRefuse()
        case 0x04: // KEEPALIVE
            return .keepalive
        case 0x05: // SESS_TERM
            return try await receiveSessTerm()
        case 0x06: // MSG_REJECT
            return try await receiveMsgReject()
        case 0x07: // SESS_INIT
            return try await receiveSessInit()
        default:
            throw CLAError.invalidProtocol("Unknown message type: \(messageType)")
        }
    }
    
    private func receiveXferSegment() async throws -> TCPCLMessage {
        let flags = try await receiveData(count: 1)[0]
        let transferId = try await receiveUInt64()
        
        // Read extension items length
        let extensionLength = try await receiveUInt32()
        let extensionData = try await receiveData(count: Int(extensionLength))
        let extensions = try TCPCLExtension.parse(from: extensionData)
        
        // Read data length
        let dataLength = try await receiveUInt64()
        let data = try await receiveData(count: Int(dataLength))
        
        return .xferSegment(flags: flags, transferId: transferId, extensionItems: extensions, data: data)
    }
    
    private func receiveXferAck() async throws -> TCPCLMessage {
        let flags = try await receiveData(count: 1)[0]
        let transferId = try await receiveUInt64()
        let length = try await receiveUInt64()
        return .xferAck(flags: flags, transferId: transferId, length: length)
    }
    
    private func receiveXferRefuse() async throws -> TCPCLMessage {
        let reasonCode = try await receiveData(count: 1)[0]
        let transferId = try await receiveUInt64()
        return .xferRefuse(reasonCode: reasonCode, transferId: transferId)
    }
    
    private func receiveSessTerm() async throws -> TCPCLMessage {
        let flags = try await receiveData(count: 1)[0]
        let reasonCode = try await receiveData(count: 1)[0]
        return .sessTerm(flags: flags, reasonCode: reasonCode)
    }
    
    private func receiveMsgReject() async throws -> TCPCLMessage {
        let reasonCode = try await receiveData(count: 1)[0]
        let rejectedMessageHeader = try await receiveData(count: 1)[0]
        return .msgReject(reasonCode: reasonCode, rejectedMessageHeader: rejectedMessageHeader)
    }
    
    private func receiveSessInit() async throws -> TCPCLMessage {
        let keepalive = try await receiveUInt16()
        let segmentMRU = try await receiveUInt64()
        let transferMRU = try await receiveUInt64()
        let nodeIdLength = try await receiveUInt16()
        let nodeId = try await receiveData(count: Int(nodeIdLength))
        
        let extensionLength = try await receiveUInt32()
        let extensionData = try await receiveData(count: Int(extensionLength))
        let extensions = try TCPCLSessionExtension.parse(from: extensionData)
        
        return .sessInit(
            keepalive: keepalive,
            segmentMRU: segmentMRU,
            transferMRU: transferMRU,
            nodeId: nodeId,
            sessionExtensionItems: extensions
        )
    }
    
    private func sendData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nwConnection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func receiveData(count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            nwConnection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, data.count == count {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: CLAError.connectionClosed)
                } else {
                    continuation.resume(throwing: CLAError.incompleteData)
                }
            }
        }
    }
    
    private func receiveUInt16() async throws -> UInt16 {
        let data = try await receiveData(count: 2)
        return UInt16(bigEndian: data.withUnsafeBytes { $0.load(as: UInt16.self) })
    }
    
    private func receiveUInt32() async throws -> UInt32 {
        let data = try await receiveData(count: 4)
        return UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
    }
    
    private func receiveUInt64() async throws -> UInt64 {
        let data = try await receiveData(count: 8)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }
}

/// TCPCLv4 Message Types
enum TCPCLMessage {
    case xferSegment(flags: UInt8, transferId: UInt64, extensionItems: [TCPCLExtension], data: Data)
    case xferAck(flags: UInt8, transferId: UInt64, length: UInt64)
    case xferRefuse(reasonCode: UInt8, transferId: UInt64)
    case keepalive
    case sessTerm(flags: UInt8, reasonCode: UInt8)
    case msgReject(reasonCode: UInt8, rejectedMessageHeader: UInt8)
    case sessInit(keepalive: UInt16, segmentMRU: UInt64, transferMRU: UInt64, nodeId: Data, sessionExtensionItems: [TCPCLSessionExtension])
    
    func encode() -> Data {
        var data = Data()
        
        switch self {
        case .xferSegment(let flags, let transferId, let extensions, let payload):
            data.append(0x01) // Message type
            data.append(flags)
            data.append(contentsOf: withUnsafeBytes(of: transferId.bigEndian) { Data($0) })
            
            // Encode extensions
            let extensionData = TCPCLExtension.encode(extensions)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(extensionData.count).bigEndian) { Data($0) })
            data.append(extensionData)
            
            // Encode data
            data.append(contentsOf: withUnsafeBytes(of: UInt64(payload.count).bigEndian) { Data($0) })
            data.append(payload)
            
        case .xferAck(let flags, let transferId, let length):
            data.append(0x02)
            data.append(flags)
            data.append(contentsOf: withUnsafeBytes(of: transferId.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Data($0) })
            
        case .xferRefuse(let reasonCode, let transferId):
            data.append(0x03)
            data.append(reasonCode)
            data.append(contentsOf: withUnsafeBytes(of: transferId.bigEndian) { Data($0) })
            
        case .keepalive:
            data.append(0x04)
            
        case .sessTerm(let flags, let reasonCode):
            data.append(0x05)
            data.append(flags)
            data.append(reasonCode)
            
        case .msgReject(let reasonCode, let rejectedMessageHeader):
            data.append(0x06)
            data.append(reasonCode)
            data.append(rejectedMessageHeader)
            
        case .sessInit(let keepalive, let segmentMRU, let transferMRU, let nodeId, let extensions):
            data.append(0x07)
            data.append(contentsOf: withUnsafeBytes(of: keepalive.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: segmentMRU.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: transferMRU.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: UInt16(nodeId.count).bigEndian) { Data($0) })
            data.append(nodeId)
            
            let extensionData = TCPCLSessionExtension.encode(extensions)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(extensionData.count).bigEndian) { Data($0) })
            data.append(extensionData)
        }
        
        return data
    }
}

/// TCPCL Extension Items
enum TCPCLExtension {
    case transferLength(UInt64)
    
    static func parse(from data: Data) throws -> [TCPCLExtension] {
        var extensions: [TCPCLExtension] = []
        var offset = 0
        
        while offset < data.count {
            guard offset + 5 <= data.count else { break }
            
            let _ = data[offset] // flags - unused for now
            let type = UInt16(bigEndian: data[offset+1..<offset+3].withUnsafeBytes { $0.load(as: UInt16.self) })
            let length = UInt16(bigEndian: data[offset+3..<offset+5].withUnsafeBytes { $0.load(as: UInt16.self) })
            offset += 5
            
            guard offset + Int(length) <= data.count else { break }
            
            if type == 0x0001 && length == 8 {
                let value = data[offset..<offset+8].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                extensions.append(.transferLength(value))
            }
            
            offset += Int(length)
        }
        
        return extensions
    }
    
    static func encode(_ extensions: [TCPCLExtension]) -> Data {
        var data = Data()
        
        for ext in extensions {
            switch ext {
            case .transferLength(let value):
                data.append(0x00) // Flags
                data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0001).bigEndian) { Data($0) }) // Type
                data.append(contentsOf: withUnsafeBytes(of: UInt16(8).bigEndian) { Data($0) }) // Length
                data.append(contentsOf: withUnsafeBytes(of: value.bigEndian) { Data($0) }) // Value
            }
        }
        
        return data
    }
}

/// TCPCL Session Extension Items
enum TCPCLSessionExtension {
    case keepaliveInterval(UInt16)
    
    static func parse(from data: Data) throws -> [TCPCLSessionExtension] {
        var extensions: [TCPCLSessionExtension] = []
        var offset = 0
        
        while offset + 5 <= data.count {
            let _ = data[offset] // flags - not used currently
            let type = data[offset+1..<offset+3].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let length = data[offset+3..<offset+5].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            
            guard offset + 5 + Int(length) <= data.count else {
                throw CLAError.invalidMessage("Invalid session extension length")
            }
            
            offset += 5
            
            // Parse known extension types
            if type == 0x0001 && length == 2 {
                let value = data[offset..<offset+2].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
                extensions.append(.keepaliveInterval(value))
            }
            
            offset += Int(length)
        }
        
        return extensions
    }
    
    static func encode(_ extensions: [TCPCLSessionExtension]) -> Data {
        var data = Data()
        
        for ext in extensions {
            switch ext {
            case .keepaliveInterval(let value):
                data.append(0x00) // Flags
                data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0001).bigEndian) { Data($0) }) // Type
                data.append(contentsOf: withUnsafeBytes(of: UInt16(2).bigEndian) { Data($0) }) // Length
                data.append(contentsOf: withUnsafeBytes(of: value.bigEndian) { Data($0) }) // Value
            }
        }
        
        return data
    }
}

/// CLA Errors
enum CLAError: Error {
    case invalidPeerAddress
    case connectionNotActive
    case connectionCancelled
    case connectionClosed
    case incompleteData
    case invalidProtocol(String)
    case unsupportedVersion(Int)
    case invalidMessage(String)
}