# Sonoic Roadmap

Sonoic is focused on becoming a dependable, cloud-first Sonos controller for the active room or group.

## Current State

The app already has:

- a SwiftUI app shell with Home, Rooms, Queue, Settings, mini-player, and player sheet
- Sonos OAuth through a Cloudflare Worker token broker
- Sonos Control API commands for playback, seek, now-playing, volume, mute, favorites, playlists, and Cloud Queue playback
- LAN discovery/bootstrap plus manual local mode for diagnostics and local-only tuning
- queue inspection, queue editing, room/group selection, and home theater controls
- Apple Music metadata, library, search, browse, and Sonos-owned playback payload research
- widget/shared state foundations and native now-playing integration
- focused tests for Control API, cloud-first state, Apple Music payloads, and shared storage
- RevenueCat-backed Sonoic Plus foundation

## Priorities

### 1. Harden Cloud Control On Real Hardware

The highest-value work is making existing behavior boring and truthful on real Sonos setups.

- verify Cloud Queue seek and Lock Screen scrubbing across Apple Music favorites, playlists, albums, and outside-app starts
- verify Control API token refresh during long playback sessions and app relaunches
- verify group/player volume and mute against grouped rooms and fixed-volume products
- verify queue editing, queue refresh, and now-playing convergence during transitions
- validate discovery and selected-target behavior across more room/group shapes
- keep diagnostics behind Advanced so the main UI stays quiet

### 2. Improve Apple Music Without Taking Over Playback

Apple Music is the first live source adapter, but Sonos should remain the playback owner.

- harden generated Sonos-owned Apple Music payloads for catalog and library items
- expand Browse lanes for recommendations, categories, curated playlists, new releases, and radio metadata
- decide which playlist, album, and song starts can preserve queue/session context safely
- keep Play visible only when an item has a trustworthy Sonos-owned playback path
- keep metadata-only states honest when playback ownership is not proven

### 3. Make Queue More Useful

Queue is already a real control surface. The next step is creation and recovery.

- improve empty-queue recovery
- add safe play-next/add-to-queue flows only where source ownership is proven
- reuse useful queue states without duplicating the player surface
- make queue mutation failures clear and recoverable

### 4. Deepen Outside-App Controls

Sonoic can publish native now-playing state, but it remains a controller, not the audio output owner.

- keep Lock Screen and Control Center controls reliable
- add App Intents for common actions
- consider Control Center controls and widgets for rooms, volume, and favorites
- preserve clear stale-state behavior whenever Sonos cannot be confirmed

### 5. Polish Home Theater And Local Tuning

The local tuning island should be useful without leaking diagnostics into the main experience.

- validate home theater controls across Arc, Beam, Ray, Amp, Sub, and surround setups
- improve unsupported-control descriptions
- keep low-level TV audio inspection under Advanced unless it becomes a useful everyday control
- avoid stale home theater state during fast room switching

### 6. Add Tasteful Sonoic Plus Personalization

Sonoic Plus should feel like support and personalization, not withheld control.

- alternate app icons
- theme and accent choices
- custom Home ordering
- extra widget styles
- saved room presets for volume, EQ, speech enhancement, and night sound

Core playback, queue editing, discovery, source browsing, Lock Screen, Control Center, and the default Home experience stay free.

## Open Questions

- How much background refresh is useful before complexity outweighs value?
- Which native now-playing behaviors can be reliable for a remote-control app?
- How far should Sonoic go into source browsing before it duplicates the Sonos app?
- Which Apple Music browse lanes matter first?
- What is the smallest reliable Sonos-owned playback path for each Apple Music item kind?
- Which home theater details deserve quiet UI, and which should stay diagnostics-only?

## Working Style

- one small vertical slice at a time
- build the real behavior, not speculative architecture
- keep Cloud and LAN boundaries explicit
- update public docs when behavior or setup changes
- use issues or PR descriptions for temporary planning rather than committing short-lived execution plans
