import Foundation
import Testing
@testable import Fyr

@Suite("Modbus TCP client with fault injection", .serialized)
struct ModbusClientTests {

    let bridge = FakeBridge()
    let factory: FakeTransportFactory
    let client: ModbusTCPClient

    init() {
        let factory = FakeTransportFactory(bridge: bridge)
        self.factory = factory
        client = ModbusTCPClient(unitId: 2, configuration: TestTiming.client, makeTransport: { factory.make() })
    }

    @Test func readsRegisters() async throws {
        #expect(try await client.readHoldingRegisters(address: 40207, count: 1) == [215])
        #expect(try await client.readHoldingRegisters(address: 40203, count: 5) == [0x3C00, 0, 80, 90, 215])
        #expect(factory.transports.count == 1)
    }

    @Test func writesRegister() async throws {
        try await client.writeSingleRegister(address: 40200, value: 101)
        #expect(await bridge.statusWord == FakeBridge.statusOn)
    }

    @Test func silentBridgeTimesOutAndClosesConnection() async throws {
        await bridge.setFault(.silent)
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await #expect(throws: ModbusError.timeout) {
                try await client.readHoldingRegisters(address: 40203, count: 1)
            }
        }
        // The deadline really fires (v1 hung until the TCP connection died).
        #expect(elapsed < TestTiming.requestTimeout + .milliseconds(500))
        #expect(await client.isConnected == false)

        // The next request reconnects and works.
        await bridge.setFault(.none)
        #expect(try await client.readHoldingRegisters(address: 40203, count: 1) == [0x3C00])
        #expect(factory.transports.count == 2)
    }

    @Test func lateReplyIsNeverTakenForTheNextRequest() async throws {
        await bridge.setFault(.lateReply(.milliseconds(700)))
        await #expect(throws: ModbusError.timeout) {
            try await client.readHoldingRegisters(address: 40207, count: 1) // temperature
        }
        await bridge.setFault(.none)
        await bridge.setRegister(40203, 0xBA04)
        // In v1 the late temperature reply could be read as the status register.
        #expect(try await client.readHoldingRegisters(address: 40203, count: 1) == [0xBA04])
        try await Task.sleep(for: .milliseconds(500)) // let the late reply arrive at the old connection
        #expect(try await client.readHoldingRegisters(address: 40203, count: 1) == [0xBA04])
    }

    @Test func staleFrameWithWrongTransactionIdIsDiscarded() async throws {
        await bridge.setFault(.staleReplyFirst)
        await bridge.setRegister(40207, 199)
        #expect(try await client.readHoldingRegisters(address: 40207, count: 1) == [199])
        #expect(try await client.readHoldingRegisters(address: 40203, count: 1) == [0x3C00])
    }

    @Test func refusedConnectionIsReported() async {
        await bridge.setFault(.refuseConnections)
        await #expect(throws: ModbusError.connectFailed(.refused)) {
            try await client.readHoldingRegisters(address: 40203, count: 1)
        }
    }

    @Test func illegalAddressKeepsTheConnection() async throws {
        await #expect(throws: ModbusError.exception(code: 0x02)) {
            try await client.readHoldingRegisters(address: 40210, count: 1)
        }
        // 40201 (flame height) is write-only on the bridge.
        await #expect(throws: ModbusError.exception(code: 0x02)) {
            try await client.readHoldingRegisters(address: 40201, count: 1)
        }
        #expect(try await client.readHoldingRegisters(address: 40203, count: 1) == [0x3C00])
        #expect(factory.transports.count == 1)
    }

    @Test func droppedConnectionFailsFast() async {
        await bridge.setFault(.dropOnRequest)
        let elapsed = await ContinuousClock().measure {
            await #expect(throws: ModbusError.connectionClosed) {
                try await client.writeSingleRegister(address: 40200, value: 3)
            }
        }
        #expect(elapsed < TestTiming.requestTimeout)
    }

    @Test func concurrentRequestsAreSerialized() async throws {
        let replyDelay = Duration.milliseconds(50)
        await bridge.setFault(.lateReply(replyDelay))
        try await withThrowingTaskGroup(of: [UInt16].self) { group in
            for _ in 0..<5 {
                group.addTask { try await client.readHoldingRegisters(address: 40203, count: 1) }
            }
            for try await values in group {
                #expect(values == [0x3C00])
            }
        }
        // Each request is only sent after the previous answer arrived.
        let times = await bridge.requestTimes
        #expect(times.count == 5)
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later - earlier >= replyDelay - .milliseconds(5))
        }
    }

    @Test func cancellationClosesThePendingRequest() async throws {
        await bridge.setFault(.silent)
        let task = Task { try await client.readHoldingRegisters(address: 40203, count: 1) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let elapsed = await ContinuousClock().measure { _ = try? await task.value }
        #expect(elapsed < .milliseconds(200))
        #expect(await client.isConnected == false)
    }
}
