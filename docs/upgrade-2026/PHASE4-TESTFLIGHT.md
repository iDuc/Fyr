# Phase 4 — TestFlight (25 October 2026)

## Done, 25 October 21:10: Fyr 2.0 (202610252004) in internal TestFlight

- App Group `group.com.vanYperen.Fyr` registered and linked by Richard;
  archive (Release, automatic signing, app + widget) and upload then worked.
- Build 202610251951 failed App Store processing: error 90626, "App Intent
  description cannot contain 'iphone'". Fixed (commit f06d114: "device" /
  "toestel") and uploaded again as **202610252004**.
- 202610252004: processing **VALID**, export compliance set (no non-exempt
  encryption), internal state **IN_BETA_TESTING**, in internal group
  **Richard** (1 tester: Richard, the Account Holder), Dutch "Wat te testen"
  (`testflight-notes-nl.txt`).
- Adding Richard by linking his existing tester record (from another app)
  returned 409; creating the tester with the group (`POST /v1/betaTesters`)
  works. `testflight_setup.py` now does that, and stops with Apple's errors
  when processing fails.
- Artifacts: `/Volumes/ThunderSloerie/BuildArtifacts/Fyr/archives/Fyr-2.0-202610252004.xcarchive`,
  `export/Fyr-2.0-202610252004-ipa/Fyr.ipa`, logs in `logs/Fyr-2.0-202610252004/`.

## Update, 25 October evening: record exists, archive blocked by the App Group

Richard created the record: **Fyr**, id 6826873658, `com.vanYperen.Fyr`,
SKU FYR-IOS, primary language **nl-NL** (checked via the API).

Tests before archiving: 115 unit tests and 5 UI tests green on the Duo
(also on the closed outer display), 0 warnings.

`scripts/testflight.sh upload` (Release, automatic signing, team SZWSVWQSP3)
fails at signing for app and widget, three times:

- with the API key: "Authentication failed: Make sure a bearer token was
  provided…", then no profile with the App Groups capability;
- with Xcode's own account: "No Accounts" (no Apple ID signed in to Xcode on
  the mini).

Cause: Fyr needs new App Store profiles that include the App Group
`group.com.vanYperen.Fyr`. Registering an App Group and assigning it to App
IDs is done by Xcode's developer services; API-key authentication cannot do
that, and the public App Store Connect API has no App Group endpoints. The
same key works for KeepOfEchoes, whose group and profiles already existed.

Done already: internal TestFlight group **Richard** (created). Adding
Richard as tester returned 409 "Tester(s) cannot be assigned"; that is
retried by `scripts/testflight_setup.py` once a build exists.

### What Richard has to click (developer portal, ~3 minutes)

1. <https://developer.apple.com/account/resources/identifiers/list/applicationGroup> → **+** → App Groups → Description *Fyr*, Identifier **group.com.vanYperen.Fyr** → Register.
2. Identifiers → **com.vanYperen.Fyr** → App Groups → Configure → tick **group.com.vanYperen.Fyr** → Save (confirm).
3. Same for **com.vanYperen.Fyr.FyrWidget**.

(Alternatively: sign in to Xcode on the Mac mini once, Settings → Accounts, with the team's Apple ID.)

Then the agent runs, in a heavy reservation:

```bash
scripts/testflight.sh upload
python3 -I scripts/testflight_setup.py <build number> docs/upgrade-2026/testflight-notes-nl.txt
```

The second step waits for processing, sets export compliance, adds Richard
and the build to the group and sets the Dutch notes
(`testflight-notes-nl.txt`).

## Earlier status: stopped at the app record

The App Store Connect API cannot create app records. Checked with key
`QSKWP2WVYV` (team SZWSVWQSP3):

- `GET /v1/apps?filter[bundleId]=com.vanYperen.Fyr` → no app.
- `POST /v1/apps` (name Fyr, nl-NL, SKU FYR-IOS, bundle id B9MYW3C72W) →
  **403 FORBIDDEN_ERROR**: "The resource 'apps' does not allow 'CREATE'.
  Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE".

`asc` (5.5.0) says the same: app records can only be created with an Apple ID
web session (`asc web apps create`), which needs Richard's Apple ID login and
two-factor code. That is out of scope for an agent. As agreed, nothing was
archived or uploaded.

Ready for the next step: both bundle IDs exist (`com.vanYperen.Fyr`
B9MYW3C72W, `com.vanYperen.Fyr.FyrWidget` 922V52R4Y5), Richard's App Store
Connect user exists (Account Holder, Admin), the key works for reading.

## What Richard has to click (about 2 minutes)

1. Go to <https://appstoreconnect.apple.com> → **Apps** → the blue **+** →
   **New App**.
2. Fill in:
   - Platforms: **iOS**
   - Name: **Fyr** (if taken: *Fyr – openhaard*)
   - Primary Language: **Dutch**
   - Bundle ID: **XC com vanYperen Fyr – com.vanYperen.Fyr**
   - SKU: **FYR-IOS**
   - User Access: **Full Access**
3. Click **Create**. Nothing else is needed (no screenshots, no review:
   internal TestFlight only).

Then tell the agent "the Fyr record exists". The rest is scripted.

## What the agent does then

```bash
# heavy reservation; archive (Release, automatic signing) + upload
sloerie-simulators run --heavy --device duo --agent claude --task "Fyr TestFlight" -- scripts/testflight.sh upload
```

- Version **2.0**, build number = UTC timestamp (`YYYYMMDDHHMM`).
- Archive and export under `/Volumes/ThunderSloerie/BuildArtifacts/Fyr/archives` and `export/`.
- `ITSAppUsesNonExemptEncryption = NO` is in Info.plist, so export
  compliance is answered by the build.
- With `scripts/asc_api.py`: wait until the build is `VALID`, create the
  internal group **Richard** (`POST /v1/betaGroups`, `isInternalGroup: true`),
  add Richard's user, add the build, set the Dutch "What to test" below
  (`betaBuildLocalizations`, locale nl-NL).

## "Wat te testen" (nl-NL, for the build)

> Fyr 2.0 – nieuw ontwerp, bediening vanuit het bedieningspaneel, widgets en live activiteit.
>
> Eerst: stel de bridge opnieuw in (de app-groep is hernoemd, oude instellingen zijn weg).
>
> Veiligheid – controleer op je iPhone:
> 1. Vergrendeld: "Hé Siri, zet Fyr uit" → werkt meteen.
> 2. Vergrendeld: "Hé Siri, zet Fyr aan" → eerst ontgrendelen, dan "De openhaard nu aansteken?". Zeg "nee": er gebeurt niets. Nog een keer en "ja": het vuur gaat aan.
> 3. Vuur uit: "Zet wave-modus aan met Fyr" → "De openhaard staat uit…", het vuur blijft uit.
> 4. Bedieningspaneel: knop Vuur uit werkt ook vergrendeld; Vuur aan vraagt ontgrendelen + bevestigen; Wave doet niets als het vuur uit is.
> 5. In de app: aan alleen met de schuifknop, uit met één tik.
>
> Verder: widget (klein/middel, ook StandBy), live activiteit op het toegangsscherm en in het Dynamic Island terwijl het vuur brandt, wave-modus, vlamhoogte (max. 1 wijziging per 10 s). Na 15 minuten zonder contact zegt de live activiteit dat de stand niet bevestigd is.
>
> De officiële DRU-app moet blijven werken: Fyr laat de verbinding los als je de app sluit.
