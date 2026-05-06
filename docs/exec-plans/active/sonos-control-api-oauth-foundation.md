# Sonos Control API OAuth Foundation

## Goal
Prepare Sonoic for the official Sonos Control API without moving playback away from the current LAN path in this pass.

## Current Behavior
- Sonoic discovers local Sonos players with Bonjour.
- Playback, queue, volume, and now-playing state use local Sonos SOAP endpoints.
- Apple Music catalog browsing can build Sonos-owned payloads for selected items, but seek can still fail for some cloud-owned playback states.

## Structural Improvement
- Add a secure Sonos OAuth foundation that keeps the client secret out of the iOS app.
- Store Sonos access and refresh tokens in Keychain.
- Add a token-broker client for server-side token exchange and refresh.
- Add a first-run onboarding shell: splash, optional Sonos account connection, speaker discovery, Home.
- Keep Settings as a status/control surface, not the primary setup path.

## Validation
- OAuth URL generation validates client ID, redirect URI, callback scheme, and scope.
- Callback parsing validates state and handles Sonos or broker errors.
- Token expiry logic uses a refresh leeway.
- Generic iOS build stays green.
- Existing LAN playback behavior is untouched.

## Out Of Scope
- Replacing LAN playback commands with Control API commands.
- Building the token broker backend.
- Creating cloud queues or playback sessions.
- Changing Apple Music browsing or Sonos favorites playback behavior.
