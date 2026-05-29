# Security And Privacy

Sonoic handles Sonos account authorization, local network access, shared app state, artwork, and Apple platform identifiers. Keep those boundaries explicit.

## Current Boundaries

- Sonos OAuth uses the Cloudflare Worker in `sonoic-sonos-worker/` so the iOS app does not contain the Sonos client secret.
- Sonos access and refresh tokens are stored in Keychain.
- Normal playback control uses the Sonos Control API.
- LAN access is used for discovery/bootstrap, manual local mode, diagnostics, and local-only tuning controls.
- Manual host configuration identifies a player on the user's LAN.
- Shared state and artwork are stored through the App Group path used by the app and widget.
- Bundle identifiers, App Group identifiers, signing, and entitlements are developer-account-specific.

## Rules

- Do not commit secrets, provisioning profiles, personal signing state, DerivedData, local Xcode user state, access tokens, refresh tokens, or private Sonos credentials.
- Do not put the Sonos client secret in Xcode, Info.plist, source control, or the iOS app.
- Keep `.local.xcconfig`, `.env`, and machine-specific files ignored.
- Do not log private network, account, token, or household details more broadly than needed for local debugging.
- Treat App Group, entitlement, bundle identifier, OAuth redirect, Worker route, and storage changes as security-sensitive.
- Prefer typed or parsed Sonos responses over guessed response shapes.

## Review Checklist

- Did the change alter entitlements, App Groups, bundle identifiers, background modes, OAuth, Worker routes, network behavior, or shared storage?
- Did the change add persistent logging, diagnostics, analytics, or external communication?
- Did the change introduce new files that might contain local machine state or secrets?
- Is any new security-sensitive behavior reflected in docs and PR notes?
