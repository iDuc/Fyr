#!/usr/bin/env python3
"""A fake DRU bridge (Modbus TCP *server*) on 127.0.0.1 for simulator screenshots.

It never connects to anything: Fyr in the simulator connects to it. Launch the
DEBUG app with `-FyrBridgeEndpoint 127.0.0.1:<port>`; the simulator shares the
Mac's loopback interface.

  python3 -I scripts/fake-dru-bridge.py --port 15020 --state burning --wave

Registers as Fyr knows them: 40203 status (0x3C00 off, 0xB804 on, bit 9 wave),
40204-40207, writes to 40200 (101 on, 3 off, 105 wave on, 7 wave off),
40201 (write-only flame height), 40220, 40250. Unit 2, register-number addressing.
"""
import argparse
import asyncio

OFF, ON, WAVE = 0x3C00, 0xB804, 0x0200


class Bridge:
    def __init__(self, burning, wave, temperature):
        status = (ON | (WAVE if wave else 0)) if burning else OFF
        self.registers = {40200: 0, 40203: status, 40204: 0, 40205: 80, 40206: 90,
                          40207: int(round(temperature * 10)), 40220: 5, 40250: 210}
        self.busy = False

    def process(self, pdu):
        if len(pdu) != 5:
            return bytes([pdu[0] | 0x80, 0x03])
        function = pdu[0]
        address = int.from_bytes(pdu[1:3], "big")
        operand = int.from_bytes(pdu[3:5], "big")
        if function == 0x03:
            data = b""
            for register in range(address, address + operand):
                if register == 40201 or register not in self.registers:
                    return bytes([0x83, 0x02])
                data += self.registers[register].to_bytes(2, "big")
            return bytes([0x03, len(data)]) + data
        if function == 0x06:
            if address not in (40200, 40201, 40220, 40250):
                return bytes([0x86, 0x02])
            if address == 40200:
                status = self.registers[40203]
                if operand == 101:
                    status = ON | (status & WAVE)
                elif operand == 3:
                    status = OFF
                elif operand == 105:
                    status |= WAVE
                elif operand == 7:
                    status &= ~WAVE
                else:
                    return bytes([0x86, 0x03])
                self.registers[40203] = status
            elif address != 40201:
                self.registers[address] = operand
            print(f"write {address} = {operand}", flush=True)
            return bytes(pdu)
        return bytes([function | 0x80, 0x01])


async def serve(bridge, reader, writer):
    if bridge.busy:  # one connection slot, like the real bridge
        writer.close()
        return
    bridge.busy = True
    try:
        while True:
            header = await reader.readexactly(7)
            length = int.from_bytes(header[4:6], "big")
            pdu = await reader.readexactly(length - 1)
            body = bridge.process(pdu) if header[6] == 2 else bytes([pdu[0] | 0x80, 0x0B])
            writer.write(header[0:4] + (len(body) + 1).to_bytes(2, "big") + header[6:7] + body)
            await writer.drain()
    except (asyncio.IncompleteReadError, ConnectionError):
        pass
    finally:
        bridge.busy = False
        writer.close()


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=15020)
    parser.add_argument("--state", choices=["burning", "off"], default="burning")
    parser.add_argument("--wave", action="store_true")
    parser.add_argument("--temperature", type=float, default=21.4)
    args = parser.parse_args()
    bridge = Bridge(args.state == "burning", args.wave, args.temperature)
    server = await asyncio.start_server(lambda r, w: serve(bridge, r, w), "127.0.0.1", args.port)
    print(f"fake DRU bridge on 127.0.0.1:{args.port} ({args.state}{', wave' if args.wave else ''})", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
