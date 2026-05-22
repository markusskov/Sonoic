# Sonos Control API OAuth Foundation

## Goal
Prepare Sonoic for the official Sonos Control API as the primary control plane while keeping credentials production-safe.

## Current Behavior
- Sonoic discovers local Sonos players with Bonjour.
- Sonos OAuth uses a Cloudflare Worker token broker so the client secret stays outside the iOS app.
- Cloud identity and command state are available for households, groups, players, playback, volume, mute, and Cloud Queue playback.
- LAN remains a local discovery, diagnostics, manual local mode, and local-only tuning layer.

## Structural Improvement
- Add a secure Sonos OAuth foundation that keeps the client secret out of the iOS app.
- Store Sonos access and refresh tokens in Keychain.
- Add a Cloudflare Worker token broker for server-side token exchange and refresh.
- Verify saved tokens with a harmless cloud read for households, groups, and players.
- Add a first-run onboarding shell: splash, optional Sonos account connection, speaker discovery, Home.
- Keep Settings as a status/control surface, not the primary setup path.
- Refresh tokens before expiry when normal Cloud commands need them.

## Validation
- OAuth URL generation validates client ID, redirect URI, callback scheme, and scope.
- Callback parsing validates state and handles Sonos or broker errors.
- Worker OAuth callback redirects back into Sonoic and token exchange uses Worker secrets.
- Token expiry logic uses a refresh leeway.
- Connected Settings state shows the cloud read result without exposing token details.
- Generic iOS build stays green.
- Worker tests stay green.
- Normal Cloud command paths do not silently fall back to LAN when authorization is expired or unavailable.

## Out Of Scope
- Full Sonos event-subscription infrastructure.
- Migrating local-only EQ/sub/surround controls that the Cloud API does not expose well enough yet.
- Changing Apple Music browsing or Sonos favorites playback behavior.
