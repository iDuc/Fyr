#!/usr/bin/env python3
"""Strictly READ-ONLY Modbus TCP register dump for the DRU / Honeywell BRDG-03EM01 bridge.

Safety rules (enforced in code, not just by convention):
  * Only function code 0x03 (Read Holding Registers) is ever sent. Any other
    function code raises before a byte leaves the machine.
  * One TCP connection at a time; it is closed when the dump ends.
  * At least MIN_GAP seconds between any two requests (the DRU bridge's read
    rate limit is 3 s).
  * Connection refused / reset is retried a few times with backoff (the bridge
    has a single connection slot, the official DRU app may hold it).

Usage: scripts/modbus-readonly-dump.py <bridge-ip> <output.json>
The bridge IP is a personal network detail: pass it on the command line and do
not commit it.
"""
import json
import socket
import struct
import sys
import time
from datetime import datetime, timezone

PORT = 502
MIN_GAP = 3.2           # seconds between requests (bridge minimum is 3 s)
POST_CONNECT_DELAY = 1.5
TIMEOUT = 6.0
CONNECT_BACKOFF = [5, 15, 30, 60]
READ_ONLY_FUNCTION = 0x03

FIRST, LAST = 40200, 40250
COUNT = LAST - FIRST + 1
# PDU start address for register 40200 under each convention.
CONVENTIONS = {
    "pdu-200 (40200-40000, register 40203 -> 203)": FIRST - 40000,
    "pdu-199 (40200-40001, register 40203 -> 202)": FIRST - 40001,
    "raw-40200 (address used by the Fyr app)": FIRST,
}


def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


class Bridge:
    def __init__(self, host):
        self.host = host
        self.sock = None
        self.tid = 0
        self.last_request = 0.0
        self.events = []

    def connect(self):
        for attempt, wait in enumerate([0] + CONNECT_BACKOFF):
            if wait:
                log(f"retrying connect in {wait}s")
                time.sleep(wait)
            try:
                s = socket.create_connection((self.host, PORT), timeout=TIMEOUT)
                s.settimeout(TIMEOUT)
                self.sock = s
                self.events.append({"t": time.time(), "event": "connected", "attempt": attempt + 1})
                log(f"connected (attempt {attempt + 1}); waiting {POST_CONNECT_DELAY}s")
                time.sleep(POST_CONNECT_DELAY)
                return True
            except OSError as e:
                self.events.append({"t": time.time(), "event": "connect-failed", "error": repr(e)})
                log(f"connect failed: {e!r}")
        return False

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            finally:
                self.sock = None
                self.events.append({"t": time.time(), "event": "closed"})
                log("connection closed")

    def _recv_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("connection closed by bridge")
            buf += chunk
        return buf

    def read_holding(self, unit, address, count):
        function = READ_ONLY_FUNCTION
        if function != 0x03:  # belt and braces: never write
            raise RuntimeError("refusing to send a non-read function code")
        gap = time.monotonic() - self.last_request
        if gap < MIN_GAP:
            time.sleep(MIN_GAP - gap)
        if self.sock is None and not self.connect():
            return {"error": "connect-failed"}
        self.tid = (self.tid + 1) & 0xFFFF
        pdu = struct.pack(">BHH", function, address, count)
        frame = struct.pack(">HHHB", self.tid, 0, len(pdu) + 1, unit) + pdu
        assert frame[7] == 0x03
        self.last_request = time.monotonic()
        result = {"unit": unit, "address": address, "count": count, "tid": self.tid,
                  "request_hex": frame.hex(" ")}
        try:
            self.sock.sendall(frame)
            header = self._recv_exact(7)
            rtid, proto, length, runit = struct.unpack(">HHHB", header)
            body = self._recv_exact(length - 1)
            result["response_hex"] = (header + body).hex(" ")
            result["mbap"] = {"tid": rtid, "proto": proto, "length": length, "unit": runit}
            if rtid != self.tid:
                result["warning"] = "transaction id mismatch"
            fc = body[0]
            if fc & 0x80:
                result["exception"] = body[1]
            else:
                n = body[1]
                regs = list(struct.unpack(f">{n // 2}H", body[2:2 + n]))
                result["registers"] = regs
        except socket.timeout:
            result["error"] = "timeout"
            self.close()  # never reuse a socket with an outstanding request
        except OSError as e:
            result["error"] = repr(e)
            self.close()
        return result


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(64)
    host, out = sys.argv[1], sys.argv[2]
    bridge = Bridge(host)
    started = datetime.now(timezone.utc).isoformat()
    reads = []

    def unit_answers(unit):
        """Read the full block for each convention; fall back to small blocks on exceptions."""
        answered = False
        for name, base in CONVENTIONS.items():
            log(f"unit {unit} {name}: read {COUNT} @ {base}")
            r = bridge.read_holding(unit, base, COUNT)
            r["convention"] = name
            r["first_register"] = FIRST
            reads.append(r)
            if "registers" in r or "exception" in r:
                answered = True
            if "exception" in r:
                # The block may span unmapped addresses: read the documented groups.
                for first, cnt in [(40200, 8), (40220, 1), (40250, 2)]:
                    sub = bridge.read_holding(unit, base + (first - FIRST), cnt)
                    sub["convention"] = name
                    sub["first_register"] = first
                    reads.append(sub)
        return answered

    try:
        if not unit_answers(2):
            for unit in (1, 3, 207):
                if unit_answers(unit):
                    break
    finally:
        bridge.close()

    with open(out, "w") as f:
        json.dump({"started": started, "finished": datetime.now(timezone.utc).isoformat(),
                   "port": PORT, "min_gap_s": MIN_GAP, "function_code": "0x03 only",
                   "events": bridge.events, "reads": reads}, f, indent=2)
    log(f"wrote {out}")


if __name__ == "__main__":
    main()
