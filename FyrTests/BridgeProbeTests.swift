import Foundation
import Testing
@testable import Fyr

@Suite("Bridge probe (discovery)", .serialized)
struct BridgeProbeTests {

    private func probe(_ bridge: FakeBridge) -> BridgeProbe {
        let factory = FakeTransportFactory(bridge: bridge)
        return BridgeProbe(client: TestTiming.client, readInterval: .milliseconds(10), makeTransport: { _ in factory.make() })
    }

    private let endpoint = BridgeEndpoint(host: "fake")

    @Test(arguments: [UInt16(0x3C00), 0xB804, 0xBA04])
    func knownStatusWordsArePlausible(value: UInt16) {
        #expect(BridgeProbe.isPlausibleStatus(value))
    }

    @Test(arguments: [UInt16(0x0000), 0xFFFF, 0x0001, 0x1234, 0x4E20])
    func otherValuesAreNot(value: UInt16) {
        #expect(!BridgeProbe.isPlausibleStatus(value))
    }

    @Test func druBridgeIsAcceptedWithReadsOnly() async {
        let bridge = FakeBridge()
        let result = await probe(bridge).probe(endpoint)
        #expect(result == .bridge(addressing: .registerNumber, status: FakeBridge.statusOff))
        #expect(await bridge.functionCodes.allSatisfy { $0 == 0x03 })
        #expect(await bridge.writes.isEmpty)
        #expect(await bridge.openConnections == 0)
    }

    @Test func otherAddressingIsFoundByReading() async {
        let bridge = await FakeBridge.burning()
        await bridge.setAddressing(.zeroBasedOffset)
        let result = await probe(bridge).probe(endpoint)
        #expect(result == .bridge(addressing: .zeroBasedOffset, status: FakeBridge.statusOn))
        #expect(await bridge.functionCodes == [0x03, 0x03])
        #expect(await bridge.writes.isEmpty)
    }

    @Test func implausibleStatusIsRejected() async {
        let bridge = FakeBridge()
        await bridge.setRegister(40203, 0x1234) // e.g. an inverter register
        #expect(await probe(bridge).probe(endpoint) == .notADRUBridge)
        #expect(await bridge.writes.isEmpty)
    }

    @Test func deviceWithoutTheRegisterIsRejected() async {
        let bridge = FakeBridge()
        await bridge.setFault(.illegalAddress)
        #expect(await probe(bridge).probe(endpoint) == .notADRUBridge)
        // Tried each addressing convention once, read-only.
        #expect(await bridge.functionCodes == [0x03, 0x03, 0x03])
    }

    @Test func wrongUnitIsRejected() async {
        let bridge = FakeBridge()
        await bridge.setUnitId(7)
        #expect(await probe(bridge).probe(endpoint) == .notADRUBridge)
    }

    @Test func silentDeviceIsNoAnswer() async {
        let bridge = FakeBridge()
        await bridge.setFault(.silent)
        #expect(await probe(bridge).probe(endpoint) == .noAnswer(.noResponse))
    }

    @Test func refusedConnectionIsNoAnswer() async {
        let bridge = FakeBridge()
        await bridge.setFault(.refuseConnections)
        #expect(await probe(bridge).probe(endpoint) == .noAnswer(.bridgeBusy))
    }
}
