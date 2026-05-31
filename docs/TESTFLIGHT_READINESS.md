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
- No secrets, provisioning profiles, access tokens, refresh tokens, or personal
  Xcode state are tracked.
- Manual hardware validation is recorded for the candidate build.

## Build, Signing, And TestFlight Checklist

- Confirm app and widget targets use release provisioning profiles for the
  intended bundle identifiers.
- Confirm the app and widget share the same App Group:
  - `SonoicApp/Sonoic.entitlements`
  - `SonoicWidgetsExtension.entitlements`
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
  - households, groups, and players load
  - logout or auth loss clears token-backed state

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
