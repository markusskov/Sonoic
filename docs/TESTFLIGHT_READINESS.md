# TestFlight Readiness

Use this checklist before an internal or external TestFlight build. It collects
the release gates that cannot be proven by ordinary unit tests alone.

Sonoic is currently scoped as an Apple Music-first Sonos controller. Do not
describe Spotify, Tidal, Sonos Radio, SoundCloud, or other services as supported
TestFlight sources until they have real source adapters and verified playback
paths.

## Local Preflight

Run the local, non-networking release preflight first:

```sh
python3 scripts/testflight_preflight.py
```

For a fuller local pass:

```sh
python3 scripts/testflight_preflight.py --run-harness --run-worker-tests
xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The script checks release-sensitive plist, entitlement, OAuth, Worker, and
tracked-file hygiene. It does not print or require real tokens or secrets.

Use [TestFlight Tester Guide](TESTFLIGHT_TESTER_GUIDE.md) for beta setup steps,
smoke testing, known boundaries, and bug report instructions.

The script does not replace:

- App Store Connect archive validation
- real Sonos hardware validation
- Cloudflare secret inspection
- TestFlight install testing
- App Privacy, support URL, or privacy policy review

## Blocker Release Gates

- A Release archive uploads to App Store Connect and installs through TestFlight.
- Sonos OAuth works from a fresh TestFlight install on a physical iPhone.
- Sonos Control API token refresh works after relaunch and during long playback.
- Normal playback commands use Sonos Cloud paths; LAN fallback stays explicit.
- Apple Music is the only live source presented as supported for beta.
- Sonoic Plus is either deliberately disabled for the build or RevenueCat
  purchase/restore validation is completed through TestFlight sandbox.
- No secrets, provisioning profiles, access tokens, refresh tokens, or personal
  Xcode state are tracked.
- Manual hardware validation is recorded for the candidate build.

## Build, Signing, And TestFlight Checklist

- Confirm app and widget targets use release provisioning profiles for the
  intended bundle identifiers.
- Confirm the Release configuration is still using:
  - app bundle ID `com.markusskov.Sonoic`
  - widget bundle ID `com.markusskov.Sonoic.SonoicWidgets`
  - development team `N2M33U7L7U`
  - matching `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for app/widget
- Confirm the app and widget share the same App Group:
  - `SonoicApp/Sonoic.entitlements`
  - `SonoicWidgetsExtension.entitlements`
- Confirm app and widget privacy manifests are present and valid:
  - `SonoicApp/PrivacyInfo.xcprivacy`
  - `SonoicWidgets/PrivacyInfo.xcprivacy`
- Confirm `SonoicApp/Info.plist` includes:
  - `sonoic` URL scheme for the OAuth callback
  - Apple Music usage description
  - local network usage description
  - `_sonos._tcp` Bonjour service
  - background audio and background fetch modes
  - `com.markusskov.Sonoic.player-refresh` in permitted BGTask identifiers
- Archive with the Release configuration.
- Upload to App Store Connect and install the uploaded build through TestFlight,
  not through Xcode.
- On first launch, verify Apple Music and local network permission prompts use
  honest user-facing language.
- Verify the widget target can read App Group state from the TestFlight build.

Safe local archive-shape checks that do not upload anything:

```sh
python3 scripts/testflight_preflight.py
xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -configuration Release -showBuildSettings
xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Do not run a distribution-signed archive or upload from automation until the
signing account, certificates, provisioning profiles, bundle IDs, version/build
number, privacy answers, and App Store Connect app record have been verified.

## Sonos OAuth And Worker Checklist

The app must not contain the Sonos client secret. The Worker owns secret
exchange.

- In the Sonos Developer Portal, verify:
  - Redirect URI: `https://sonos.ryvus.app/oauth/sonos/callback`
  - Event Callback URL: `https://sonos.ryvus.app/api/sonos/events`
  - Required scope includes `playback-control-all`
- In Cloudflare, verify Worker secrets are set without printing them:
  - `SONOS_CLIENT_SECRET`
  - `BROKER_CODE_SIGNING_SECRET`
- Confirm the Worker route responds:

```sh
curl https://sonos.ryvus.app/healthz
```

Expected response body is `{"ok":true}` and the response should include
`Cache-Control: no-store`.

- Confirm `sonoic-sonos-worker/wrangler.jsonc` has:
  - `SONOS_CLIENT_ID`
  - `SONOS_REDIRECT_URI`
  - `SONOIC_APP_REDIRECT_URI`
  - Durable Object bindings for broker-code redemption and Cloud Queues
- Confirm `Config/SonoicOAuth.local.xcconfig` is local-only and ignored.
- Confirm the iOS app bundle uses build settings for OAuth URLs and client ID,
  not hard-coded secret values.
- Fresh-install the TestFlight build and verify:
  - Sonos login opens
  - Worker callback returns to `sonoic://sonos-auth`
  - token exchange succeeds
  - token refresh succeeds after relaunch or expiry without showing login again
  - households, groups, and players load
  - logout or auth loss clears token-backed state

## Draft PR OAuth Validation Notes

Do not post these until the candidate build is ready for manual validation.

- Install the TestFlight build fresh, connect Sonos, and confirm the app returns
  through `sonoic://sonos-auth` without exposing a raw Sonos auth code.
- Relaunch the app and verify Sonos Cloud state loads without a second login.
- Exercise token refresh by using a long-running session or a controlled expiry
  window; confirm refresh succeeds and diagnostics do not include access tokens,
  refresh tokens, or the Sonos client secret.
- Disconnect Sonos, relaunch, and verify the app shows disconnected state and
  does not send Sonos Cloud commands until reconnecting.
- Record Worker route, app build number, device/iOS version, Sonos account, and
  room/group shape for the validation note.

## Draft PR Archive Validation Notes

Do not post these until Charles is asking for manual archive/TestFlight upload
validation.

- Create a Release archive from Xcode Organizer for scheme `Sonoic` using team
  `N2M33U7L7U`; do not change bundle IDs while archiving.
- Confirm Organizer validation shows app bundle `com.markusskov.Sonoic`, widget
  bundle `com.markusskov.Sonoic.SonoicWidgets`, shared App Group
  `group.com.markusskov.sonoic.shared`, and embedded privacy manifests.
- Upload to App Store Connect, wait for processing, and record any ITMS warning
  or privacy/signing email verbatim without including secrets.
- Install the processed build through TestFlight, not Xcode, before running the
  manual Sonos OAuth and hardware validation matrix.
- Record archive version/build number, Xcode version, signing team, upload time,
  App Store Connect processing result, and TestFlight build number.

## Draft PR Support And Bug Report Notes

Do not post these until the candidate build is ready for tester instructions.

- Ask testers to include build number, iPhone model, iOS version, Sonos products,
  grouped-room shape, source type, exact steps, expected result, actual result,
  and approximate local time of the failure.
- Ask testers to paste the redacted support summary from Settings > Advanced >
  Support Summary when reporting playback, auth, Cloud Queue, room selection,
  or queue/mini-player failures.
- Ask for screenshots or a short screen recording when the UI appears stale,
  unavailable, or inconsistent with Sonos.
- Do not ask testers to paste raw auth URLs, OAuth codes, HTTP headers, access
  tokens, refresh tokens, Cloudflare secrets, local OAuth config, or unredacted
  console logs.
- If a tester can reproduce with a physical speaker, ask whether playback was
  started inside Sonoic, inside the Sonos app, or from another controller before
  the failure.

Manual check still required before external TestFlight: induce one harmless
failure on a physical device, copy the support summary, and confirm it has useful
auth/cloud/queue/playback state without raw local IP addresses, Sonos player IDs,
OAuth tokens, auth codes, Worker secrets, or private URLs.

## Privacy And Secrets Audit

- Run:

```sh
python3 scripts/testflight_preflight.py
git status --short
```

- Inspect tracked files for:
  - `.env`, `.local.xcconfig`, provisioning profiles, certificates, archives,
    private keys, and personal Xcode state
  - raw OAuth access tokens or refresh tokens
  - raw Sonos client secret values
  - crash or diagnostics logs with account, token, or private network details
- Confirm local secrets remain outside git:
  - `Config/SonoicOAuth.local.xcconfig`
  - Cloudflare Worker secrets
  - Apple signing assets
  - RevenueCat keys if configured locally
- Confirm App Privacy answers cover:
  - Sonos account authorization
  - Apple Music library/search access
  - local network discovery
  - diagnostics, analytics, or crash reporting if enabled
  - App Group shared state and artwork caching

## Sonoic Plus Purchase Checklist

Sonoic Plus uses RevenueCat for the paywall and entitlement check. The iOS app
must not contain private App Store Connect credentials or secret server keys.

- Confirm `SonoicApp/Info.plist` reads:
  - `RevenueCatAPIKey` from `$(REVENUECAT_API_KEY)`
  - `SonoicPlusEntitlementIdentifier` from
    `$(SONOIC_PLUS_ENTITLEMENT_IDENTIFIER)`
- Confirm `Config/SonoicOAuth.local.xcconfig` is the only place local RevenueCat
  SDK key overrides are kept.
- Confirm the TestFlight candidate intentionally uses entitlement identifier
  `plus`, unless RevenueCat has been changed and docs/tests are updated
  together.
- If Plus is not part of the candidate, verify Settings shows Plus as disabled
  instead of implying a broken purchase.
- If Plus is part of the candidate, verify in TestFlight sandbox:
  - the paywall opens without exposing API keys or customer identifiers
  - purchase success unlocks the `plus` entitlement
  - restore purchases succeeds for an entitled Apple ID
  - network/offline failure copy is understandable and does not expose RevenueCat
    request details
  - relaunch preserves the unlocked state after RevenueCat refresh

## Manual Hardware Validation Matrix

Record the device, iOS version, Sonos products, grouped-room shape, app build
number, Worker route, and Sonos account used for each pass.

| Area | Scenario | Expected Result |
| --- | --- | --- |
| OAuth | Fresh install, login, relaunch | Auth state stays ready and Cloud snapshot loads |
| Token refresh | Long playback or forced expiry/relaunch | Refresh succeeds without requiring full login |
| Target selection | Single room, grouped room, selected room change | Commands target the intended Sonos group |
| Transport | Play, pause, next, previous | UI updates honestly and stale commands fail visibly |
| Seek | Scrubber seek and Lock Screen scrub | Seek lands near requested position or shows unavailable |
| Volume/mute | Group, player, fixed-volume product | Unsupported volume states are not shown as successful |
| Favorites | Direct favorite song and favorite playlist row | Direct favorites use Control API favorites; no fake single-item Cloud Queue |
| Apple Music | Song, album, playlist, library item, catalog item | Play appears only for trustworthy Sonos-owned paths |
| Cloud Queue | Create/load, skip, current-item mapping, relaunch | Queue ownership and runtime context remain consistent |
| Failure recovery | Worker offline, no network, 401/403, 500 | Rollback and diagnostics match the failure type |
| Queue UI | Empty queue, outside-app Sonos starts, refresh | Stale or unavailable state is visible |
| Widgets | App killed, widget reload, artwork cache | Widget reflects shared state or honest unavailable state |
| Lock Screen | Play/pause/seek from outside app | Controls work when metadata supports them |
| Background refresh | Device idle/relaunch | No BGTask crash; state refresh is conservative |
| LAN/manual mode | Discovery, manual host, home theater tuning | LAN behavior stays explicit and diagnostic/local-only |

## TestFlight Notes To Include

- Sonoic controls Sonos speakers; the phone is not the audio output.
- Apple Music is the current live source integration.
- Other music services are not supported in this beta.
- A Sonos account, Sonos household, and network access to speakers are required.
- Some Lock Screen, Control Center, queue, and artwork behavior depends on what
  Sonos exposes for the active source.
- Ask testers to include room/group shape, Sonos product names, iOS version,
  build number, and whether playback started inside Sonoic or outside it.
- Link testers to [TestFlight Tester Guide](TESTFLIGHT_TESTER_GUIDE.md) so
  setup, smoke pass, support summary, and privacy expectations are explicit.
