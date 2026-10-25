"""After an upload: wait for processing, then set up internal TestFlight testing.

  python3 -I scripts/testflight_setup.py <build number> [notes file]

- waits until the build is processed (VALID), at most 60 minutes;
- export compliance: usesNonExemptEncryption = false (Info.plist already says NO);
- internal beta group "Richard" (created if missing);
- Richard (the Account Holder) as tester in that group, matched by his App
  Store Connect user, never printed;
- the build in the group, and Dutch "What to test" notes (nl-NL).
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_api import request  # noqa: E402

BUNDLE_ID = "com.vanYperen.Fyr"
GROUP_NAME = "Richard"


def call(method, path, body=None, ok=(200, 201, 204)):
    status, result = request(method, path, body)
    if status not in ok:
        sys.exit(f"{method} {path.split('?')[0]} -> {status}: {json.dumps(result.get('errors', result))[:600]}")
    return result


def main():
    build_number = sys.argv[1]
    notes = open(sys.argv[2]).read().strip() if len(sys.argv) > 2 else None

    app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    app_id = app["id"]

    # 1. Wait for the build to appear and finish processing.
    deadline = time.time() + 60 * 60
    build = None
    while time.time() < deadline:
        found = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={build_number}"
                            "&fields[builds]=version,processingState,usesNonExemptEncryption,expired")["data"]
        if found:
            build = found[0]
            state = build["attributes"]["processingState"]
            print(f"build {build_number}: {state}", flush=True)
            if state != "PROCESSING":
                break
        else:
            print(f"build {build_number}: not visible yet", flush=True)
        time.sleep(60)
    if not build or build["attributes"]["processingState"] != "VALID":
        sys.exit(f"build not valid: {build and build['attributes']}")
    build_id = build["id"]

    # 2. Export compliance.
    if build["attributes"].get("usesNonExemptEncryption") is None:
        call("PATCH", f"/v1/builds/{build_id}", {"data": {
            "type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}})
    print("export compliance: no non-exempt encryption", flush=True)

    # 3. Internal group.
    groups = call("GET", f"/v1/apps/{app_id}/betaGroups?fields[betaGroups]=name,isInternalGroup")["data"]
    group = next((g for g in groups if g["attributes"]["name"] == GROUP_NAME), None)
    if group is None:
        group = call("POST", "/v1/betaGroups", {"data": {
            "type": "betaGroups",
            "attributes": {"name": GROUP_NAME, "isInternalGroup": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print(f"group {GROUP_NAME}: created", flush=True)
    else:
        print(f"group {GROUP_NAME}: exists (internal={group['attributes']['isInternalGroup']})", flush=True)
    group_id = group["id"]

    # 4. Richard: the Account Holder.
    users = call("GET", "/v1/users?fields[users]=firstName,lastName,roles,username&limit=200")["data"]
    richard = next(u for u in users if "ACCOUNT_HOLDER" in u["attributes"]["roles"])
    email = richard["attributes"]["username"]
    testers = call("GET", f"/v1/betaGroups/{group_id}/betaTesters?fields[betaTesters]=email&limit=200")["data"]
    if any((t["attributes"].get("email") or "").lower() == email.lower() for t in testers):
        print("tester: Richard already in group", flush=True)
    else:
        existing = call("GET", f"/v1/betaTesters?filter[email]={email}&fields[betaTesters]=email")["data"]
        if existing:
            call("POST", f"/v1/betaGroups/{group_id}/relationships/betaTesters",
                 {"data": [{"type": "betaTesters", "id": existing[0]["id"]}]})
        else:
            call("POST", "/v1/betaTesters", {"data": {
                "type": "betaTesters",
                "attributes": {"email": email, "firstName": richard["attributes"]["firstName"],
                               "lastName": richard["attributes"]["lastName"]},
                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group_id}]}}}})
        print("tester: Richard added", flush=True)

    # 5. Build in the group.
    call("POST", f"/v1/betaGroups/{group_id}/relationships/builds",
         {"data": [{"type": "builds", "id": build_id}]})
    print("build added to group", flush=True)

    # 6. What to test (nl-NL).
    if notes:
        locs = call("GET", f"/v1/builds/{build_id}/betaBuildLocalizations")["data"]
        loc = next((l for l in locs if l["attributes"]["locale"] == "nl-NL"), None)
        if loc:
            call("PATCH", f"/v1/betaBuildLocalizations/{loc['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": notes}}})
        else:
            call("POST", "/v1/betaBuildLocalizations", {"data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": "nl-NL", "whatsNew": notes},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        print("what to test (nl-NL): set", flush=True)

    # Summary.
    state = call("GET", f"/v1/builds/{build_id}?fields[builds]=version,processingState,usesNonExemptEncryption")
    detail = call("GET", f"/v1/builds/{build_id}/buildBetaDetail")["data"]["attributes"]
    print(json.dumps({"build": state["data"]["attributes"], "beta": detail}, indent=1))


if __name__ == "__main__":
    main()
