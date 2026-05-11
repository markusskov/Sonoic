# Sonos Control API OAuth Foundation

> Status: Superseded by the Cloud Control Spine plan. This file is retained as historical context for the OAuth foundation slice; "LAN untouched" statements below describe the narrow PR boundary at the time, not the current control-plane decision.

## Goal
Prepare Sonoic for the official Sonos Control API without moving playback away from the current LAN path in this pass.

## Current Behavior
- Sonoic discovers local Sonos players with Bonjour.
- Playback, queue, volume, and now-playing state use local Sonos SOAP endpoints.
- Apple Music catalog browsing can build Sonos-owned payloads for selected items, but seek can still fail for some cloud-owned playback states.

## Structural Improvement
- Add a secure Sonos OAuth foundation that keeps the client secret out of the iOS app.
- Store Sonos access and refresh tokens in Keychain.
- Add a Cloudflare Worker token broker for server-side token exchange and refresh.
- Verify saved tokens with a harmless cloud read for households, groups, and players.
- Add a first-run onboarding shell: splash, optional Sonos account connection, speaker discovery, Home.
- Keep Settings as a status/control surface, not the primary setup path.

## Validation
- OAuth URL generation validates client ID, redirect URI, callback scheme, and scope.
- Callback parsing validates state and handles Sonos or broker errors.
- Worker OAuth callback redirects back into Sonoic and token exchange uses Worker secrets.
- Token expiry logic uses a refresh leeway.
- Connected Settings state shows the cloud read result without exposing token details.
- Generic iOS build stays green.
- Worker tests stay green.
- Existing LAN playback behavior is untouched.

## Out Of Scope
- Replacing LAN playback commands with Control API commands.
- Creating cloud queues or playback sessions.
- Changing Apple Music browsing or Sonos favorites playback behavior.
