"""Minimal App Store Connect API client for Fyr's TestFlight setup.

Credentials are never stored in this repo and never printed:
- key id:   ASC_KEY_ID (default QSKWP2WVYV)
- key file: ASC_KEY_PATH (default ../AuthKey_<key id>.p8 next to the projects)
- issuer:   ASC_ISSUER_ID, or read from ASC_ENV_FILE (default: KeepOfEchoes'
            .env.release, same team) - only that one value is read.

The JWT is signed with openssl (ES256), so no Python packages are needed.

Usage (run with python3 -I):
  asc_api.py get  /v1/apps?filter[bundleId]=com.vanYperen.Fyr
  asc_api.py post /v1/betaGroups '<json body>'
  asc_api.py patch /v1/builds/<id> '<json body>'
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEV = "/Volumes/ThunderSloerie/Development"
KEY_ID = os.environ.get("ASC_KEY_ID", "QSKWP2WVYV")
KEY_PATH = os.environ.get("ASC_KEY_PATH", f"{DEV}/AuthKey_{KEY_ID}.p8")
ENV_FILE = os.environ.get("ASC_ENV_FILE", f"{DEV}/KeepOfEchoes/.env.release")
BASE = "https://api.appstoreconnect.apple.com"


def issuer_id():
    if os.environ.get("ASC_ISSUER_ID"):
        return os.environ["ASC_ISSUER_ID"]
    for line in open(ENV_FILE):
        line = line.strip()
        if line.startswith("ASC_ISSUER_ID="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit("ASC_ISSUER_ID not found")


def _b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_to_raw(der):
    # ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER }
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        length = der[i + 1]
        parts.append(der[i + 2:i + 2 + length].lstrip(b"\x00").rjust(32, b"\x00"))
        i += 2 + length
    return parts[0] + parts[1]


def token():
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer_id(), "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = (_b64(json.dumps(header).encode()) + "." + _b64(json.dumps(payload).encode())).encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY_PATH], input=signing_input,
                         capture_output=True, check=True).stdout
    return signing_input.decode() + "." + _b64(_der_to_raw(der))


def request(method, path, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except ValueError:
            return error.code, {"raw": raw.decode(errors="replace")}


if __name__ == "__main__":
    method = sys.argv[1].upper()
    path = sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    status, result = request(method, path, body)
    print(json.dumps({"status": status, "body": result}, indent=1))
