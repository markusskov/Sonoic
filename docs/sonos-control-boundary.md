# Sonos Control Boundary

Sonoic's control-plane rule is:

> Cloud is the normal control plane. LAN is a local-tools layer.

This boundary exists so contributors do not accidentally create two silent truths for the same user action.

## Cloud-Owned Surfaces

These surfaces should use Sonos Control API identity and commands when available:

- account connection
- household, group, and player identity
- play, pause, next, previous
- seek
- main player volume and mute
- favorite and playlist starts when the item can be matched to Cloud content
- Lock Screen and Control Center command routing

If a Cloud-owned command cannot run, Sonoic should show or record Cloud unavailable. It should not silently switch to LAN.

## Local-Tools Surfaces

These surfaces may use same-network LAN/SOAP because Cloud support is missing, incomplete, or still unverified:

- Bonjour/local discovery
- manual host troubleshooting
- queue inspection, jump, clear, remove, and reorder
- generated source playlist queues until Sonoic hosts Cloud Queue API endpoints
- now-playing metadata refresh while Cloud metadata coverage is still being validated
- EQ, Sub level, bonded accessory inspection, TV diagnostics, speech enhancement, and night sound until each Cloud endpoint is verified per device family
- Advanced diagnostics

Local tools should stay honest in naming, docs, and UI. They are not a hidden fallback for normal playback.

## Migration Rule

When moving a surface from Local Tools to Cloud:

1. Add the Control API endpoint to `SonosControlAPIClient`.
2. Route the user-facing action through a Cloud wrapper in `SonoicModel`.
3. Require the active target to match a verified Cloud command target.
4. Preserve local state optimistically only until the Cloud command fails.
5. On failure, restore local UI state and record Cloud unavailable.
6. Keep the old LAN method only behind an explicit local-tools call site.
7. Add device verification notes for the affected surface.

