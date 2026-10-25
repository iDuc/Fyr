import Foundation
import Testing
@testable import Fyr

/// The real `NWBridgeTransport` against `ModbusLoopbackServer` on 127.0.0.1.
@Suite("Loopback TCP integration", .serialized)
struct LoopbackIntegrationTests {

    private func client(for server: ModbusLoopbackServer) -> ModbusTCPClient {
        let endpoint = server.endpoint
        return ModbusTCPClient(unitId: 2, configuration: TestTiming.client, makeTransport: {
            NWBridgeTransport(endpoint: endpoint)
        })
    }

    @Test func readsAndWritesOverTCP() async throws {
        let server = try ModbusLoopbackServer(bridge: FakeBridge())
        try await server.start()
        defer { server.stop() }

        let client = client(for: server)
        try await client.writeSingleRegister(address: 40200, value: 101)
        #expect(try await client.readHoldingRegisters(address: 40203, count: 5) == [0xB804, 0, 80, 90, 215])
        await client.disconnect()
    }

    @Test func repliesSplitIntoSingleBytesAreReassembled() async throws {
        let bridge = FakeBridge()
        await bridge.setFault(.splitReplies)
        let server = try ModbusLoopbackServer(bridge: bridge)
        try await server.start()
        defer { server.stop() }

        let client = client(for: server)
        #expect(try await client.readHoldingRegisters(address: 40203, count: 2) == [0x3C00, 0])
        await client.disconnect()
    }

    @Test func staleFrameInTheSameSegmentIsDiscarded() async throws {
        let bridge = FakeBridge()
        await bridge.setFault(.staleReplyFirst)
        let server = try ModbusLoopbackServer(bridge: bridge)
        try await server.start()
        defer { server.stop() }

        let client = client(for: server)
        #expect(try await client.readHoldingRegisters(address: 40207, count: 1) == [215])
        await client.disconnect()
    }

    @Test func silentServerTimesOutAndRecovers() async throws {
        let bridge = FakeBridge()
        await bridge.setFault(.silent)
        let server = try ModbusLoopbackServer(bridge: bridge)
        try await server.start()
        defer { server.stop() }

        let client = client(for: server)
        let elapsed = await ContinuousClock().measure {
            await #expect(throws: ModbusError.timeout) {
                try await client.readHoldingRegisters(address: 40203, count: 1)
            }
        }
        #expect(elapsed < TestTiming.requestTimeout + .seconds(1))

        await bridge.setFault(.none)
        try await Task.sleep(for: .milliseconds(100)) // server notices the closed connection
        #expect(try await client.readHoldingRegisters(address: 40203, count: 1) == [0x3C00])
        await client.disconnect()
    }

    @Test func closedPortIsReportedAsRefused() async throws {
        let server = try ModbusLoopbackServer(bridge: FakeBridge())
        try await server.start()
        let endpoint = server.endpoint
        server.stop()
        try await Task.sleep(for: .milliseconds(100))

        let client = ModbusTCPClient(unitId: 2, configuration: TestTiming.client, makeTransport: {
            NWBridgeTransport(endpoint: endpoint)
        })
        await #expect(throws: ModbusError.connectFailed(.refused)) {
            try await client.connect()
        }
    }

    @Test func serviceEndToEnd() async throws {
        let bridge = FakeBridge()
        let server = try ModbusLoopbackServer(bridge: bridge)
        try await server.start()
        defer { server.stop() }

        let service = DRUFireplaceService(
            configuration: TestTiming.service(),
            flameHeightStore: MemoryFlameHeightStore(),
            statusSink: { _, _ in }
        )
        await service.configure(endpoint: server.endpoint)
        try await service.turnOn(authorization: .appSlider)
        try await service.setWaveMode(enabled: true)
        try await service.setFlameHeight(65)
        let status = try await service.fetchStatus()
        #expect(status.isOn && status.ecoModeActive)
        #expect(status.flameHeight == 65)
        #expect(await bridge.flameHeightTarget == 65)

        await service.releaseConnection()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await bridge.openConnections == 0)
    }
}
