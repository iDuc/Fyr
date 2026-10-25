import Foundation
import Testing
@testable import Fyr

@Suite("Modbus framing")
struct ModbusProtocolTests {

    @Test func readRequestGoldenBytes() {
        let pdu = ModbusProtocol.readHoldingRegistersPDU(address: 40203, count: 1)
        let frame = ModbusProtocol.frame(transactionId: 1, unitId: 2, pdu: pdu)
        // tid 0001, protocol 0000, length 0006, unit 02, fc 03, address 9D0B (40203), count 0001
        #expect(frame == [0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x02, 0x03, 0x9D, 0x0B, 0x00, 0x01])
    }

    @Test func writeRequestGoldenBytes() {
        let pdu = ModbusProtocol.writeSingleRegisterPDU(address: 40200, value: 101)
        let frame = ModbusProtocol.frame(transactionId: 7, unitId: 2, pdu: pdu)
        #expect(frame == [0x00, 0x07, 0x00, 0x00, 0x00, 0x06, 0x02, 0x06, 0x9D, 0x08, 0x00, 0x65])
    }

    @Test func parsesHeader() throws {
        let header = try ModbusProtocol.parseHeader([0x12, 0x34, 0x00, 0x00, 0x00, 0x05, 0x02])
        #expect(header == .init(transactionId: 0x1234, protocolId: 0, length: 5, unitId: 2))
        #expect(header.pduLength == 4)
    }

    @Test(arguments: [
        [UInt8]([0x00, 0x01, 0x00, 0x01, 0x00, 0x05, 0x02]), // protocol id 1
        [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02],          // length 0
        [0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x02],          // length too short for any PDU
        [0x00, 0x01, 0x00, 0x00, 0x00, 0xFF, 0x02],          // length 255 > 254
        [0x00, 0x01, 0x00, 0x00, 0x00, 0x05],                // truncated header
    ])
    func rejectsInvalidHeaders(bytes: [UInt8]) {
        #expect(throws: ModbusError.self) { try ModbusProtocol.parseHeader(bytes) }
    }

    @Test func parsesReadResponse() throws {
        let values = try ModbusProtocol.parseReadHoldingRegisters(pdu: [0x03, 0x04, 0xB8, 0x04, 0x00, 0xD7], expectedCount: 2)
        #expect(values == [0xB804, 215])
    }

    @Test func readResponseWithWrongByteCountIsRejected() {
        #expect(throws: ModbusError.self) {
            try ModbusProtocol.parseReadHoldingRegisters(pdu: [0x03, 0x02, 0xB8, 0x04], expectedCount: 2)
        }
    }

    @Test func exceptionResponseIsReported() {
        #expect(throws: ModbusError.exception(code: 0x02)) {
            try ModbusProtocol.parseReadHoldingRegisters(pdu: [0x83, 0x02], expectedCount: 1)
        }
        #expect(throws: ModbusError.exception(code: 0x06)) {
            try ModbusProtocol.parseWriteSingleRegister(pdu: [0x86, 0x06], address: 40200, value: 3)
        }
    }

    @Test func wrongFunctionCodeIsRejected() {
        #expect(throws: ModbusError.unexpectedFunctionCode(expected: 0x03, actual: 0x06)) {
            try ModbusProtocol.parseReadHoldingRegisters(pdu: [0x06, 0x9D, 0x08, 0x00, 0x65], expectedCount: 1)
        }
    }

    @Test func writeResponseMustEchoRequest() throws {
        try ModbusProtocol.parseWriteSingleRegister(pdu: [0x06, 0x9D, 0x08, 0x00, 0x65], address: 40200, value: 101)
        #expect(throws: ModbusError.self) {
            try ModbusProtocol.parseWriteSingleRegister(pdu: [0x06, 0x9D, 0x08, 0x00, 0x03], address: 40200, value: 101)
        }
    }
}

@Suite("DRU registers and status")
struct DRURegisterTests {

    @Test func addressingConventions() {
        #expect(DRUAddressing.registerNumber.pduAddress(for: .status) == 40203)
        #expect(DRUAddressing.zeroBasedOffset.pduAddress(for: .status) == 202)
        #expect(DRUAddressing.oneBasedOffset.pduAddress(for: .status) == 203)
        #expect(DRUAddressing.zeroBasedOffset.pduAddress(for: .action) == 199)
        #expect(DRUAddressing.oneBasedOffset.pduAddress(for: .action) == 200)
        #expect(DRUAddressing.default == .registerNumber)
    }

    /// Fyr v1's "offset 1" computed 40203 + 1 = 40204 (the error register), and
    /// would have sent "turn on" to the flame height register. Every convention
    /// must keep registers distinct and in order.
    @Test(arguments: DRUAddressing.allCases)
    func addressingKeepsRegistersDistinct(addressing: DRUAddressing) {
        let addresses = DRURegister.allCases.map { addressing.pduAddress(for: $0) }
        #expect(Set(addresses).count == DRURegister.allCases.count)
        for register in DRURegister.allCases {
            let expectedDelta = Int(register.rawValue) - Int(DRURegister.action.rawValue)
            let delta = Int(addressing.pduAddress(for: register)) - Int(addressing.pduAddress(for: .action))
            #expect(delta == expectedDelta)
        }
    }

    @Test func statusWordDecoding() {
        let off = DRUStatusWord(rawValue: 0x3C00)
        #expect(!off.isOn && !off.waveModeActive)

        let on = DRUStatusWord(rawValue: 0xB804)
        #expect(on.isOn && !on.waveModeActive)

        let wave = DRUStatusWord(rawValue: 0xBA04)
        #expect(wave.isOn && wave.waveModeActive)

        #expect(!DRUStatusWord(rawValue: 0).isOn)
    }

    @Test func statusFromRegisters() {
        let status = FireplaceStatus(
            registers: [.status: 0xBA04, .errorCode: 0, .rssiGateway: 80, .rssiFireplace: 90, .temperature: 215],
            lastSetFlameHeight: 70
        )
        #expect(status.isOn)
        #expect(status.ecoModeActive)
        #expect(status.currentTemperature == 21.5)
        #expect(status.signalStrength == -45)
        #expect(status.flameHeight == 70)
        #expect(status.flameHeightIsKnown)
        #expect(status.errorCode == nil)
        #expect(status.rawStatus == 0xBA04)
    }

    @Test func unknownFlameHeightUsesDefault() {
        let status = FireplaceStatus(registers: [.status: 0x3C00, .errorCode: 1], lastSetFlameHeight: nil)
        #expect(!status.isOn)
        #expect(status.flameHeight == DRUConstants.defaultFlameHeight)
        #expect(!status.flameHeightIsKnown)
        #expect(status.errorCode == .f01)
    }

    @Test func bridgeErrorMapping() {
        #expect(BridgeError(.connectFailed(.refused)) == .bridgeBusy)
        #expect(BridgeError(.connectFailed(.unreachable)) == .unreachable)
        #expect(BridgeError(.connectFailed(.networkDown)) == .networkUnavailable)
        #expect(BridgeError(.timeout) == .noResponse)
        #expect(BridgeError(.connectionClosed) == .connectionLost)
        #expect(BridgeError(.exception(code: 0x06)) == .deviceBusy)
        #expect(BridgeError(.exception(code: 0x02)) == .rejected(exceptionCode: 2))
        #expect(BridgeError.bridgeBusy.recoverySuggestion != nil)
    }

    @Test func endpointParsing() {
        #expect(BridgeEndpoint("10.0.0.5") == BridgeEndpoint(host: "10.0.0.5", port: 502))
        #expect(BridgeEndpoint("127.0.0.1:15020") == BridgeEndpoint(host: "127.0.0.1", port: 15020))
        #expect(BridgeEndpoint("host:notaport") == nil)
        #expect(BridgeEndpoint(":502") == nil)
        #expect(BridgeEndpoint("a:1:2") == nil)
    }
}

@Suite("Rate limiter")
struct RateLimiterTests {

    @Test func productionIntervalsMatchDRULimits() {
        #expect(RateLimiter.Intervals.production == .init(read: .seconds(3), write: .seconds(3), flameHeight: .seconds(10)))
    }

    @Test func secondRequestMustWait() async {
        let limiter = RateLimiter(intervals: .init(read: .seconds(3), write: .seconds(3), flameHeight: .seconds(10)))
        #expect(await limiter.tryAcquire(.read) == nil)
        let wait = await limiter.tryAcquire(.read)
        #expect(wait != nil)
        #expect(wait! > .milliseconds(2900) && wait! <= .seconds(3))
        // Reads and writes are limited independently.
        #expect(await limiter.tryAcquire(.write) == nil)
    }

    @Test func flameHeightCountsAsWrite() async {
        let limiter = RateLimiter(intervals: .init(read: .seconds(3), write: .seconds(3), flameHeight: .seconds(10)))
        #expect(await limiter.tryAcquire(.flameHeight) == nil)
        #expect(await limiter.tryAcquire(.write) != nil)
        #expect(await limiter.remaining(.flameHeight) > .seconds(9))
    }

    @Test func slotIsGrantedAfterInterval() async throws {
        let limiter = RateLimiter(intervals: .init(read: .milliseconds(100), write: .milliseconds(100), flameHeight: .milliseconds(100)))
        #expect(await limiter.tryAcquire(.flameHeight) == nil)
        try await Task.sleep(for: .milliseconds(120))
        #expect(await limiter.tryAcquire(.flameHeight) == nil)
    }

    @Test func concurrentCallersCannotBothPass() async {
        let limiter = RateLimiter(intervals: .production)
        let granted = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask { await limiter.tryAcquire(.flameHeight) == nil }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(granted == 1)
    }
}
