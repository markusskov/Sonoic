# Quality Score

This file is a lightweight agent-readable snapshot of product and engineering health. Update it when a meaningful slice lands or when a gap becomes visible.

## Snapshot

Last reviewed: 2026-04-27

| Area | Grade | Notes |
| --- | --- | --- |
| Product direction | B | Focused Cloud-first Sonos direction is clear in `README.md` and `plan.md`, with local tools kept as an explicit same-network island. |
| App shell | B | Core tabs, mini-player, player sheet, settings, rooms, and queue surfaces exist. |
| Sonos control | B | Real discovery, room/group selection, queue control, home theater controls, and playback commands exist. More multi-household validation is still needed. |
| Native now-playing path | C+ | Lock Screen metadata, artwork, controls, progress, and scrubbing exist, but ownership is still sensitive because Sonos remains the audio owner. |
| Widget and shared state | C+ | Shared state exists, with room to harden outside-app freshness and failure handling. |
| Automated tests | D | No test target is visible yet. Use manual and build verification until tests are introduced. |
| Agent harness | C | Initial map, docs, execution-plan structure, and harness check now exist. More structural checks can follow. |

## Current Highest Leverage Improvements

- Stabilize native now-playing behavior without hiding stale or unavailable state.
- Introduce focused tests or checkable fixtures around Sonos parsing and state transitions.
- Add structural dependency checks once the app/shared/widget boundaries grow.
- Add simulator or device smoke-test scripts for the main control flows.

## Grade Meanings

- `A`: reliable, validated, and easy for future agents to extend.
- `B`: solid and understandable, with known smaller gaps.
- `C`: useful but still needs hardening or clearer validation.
- `D`: mostly manual, fragile, or missing validation.
- `F`: actively misleading, broken, or unsafe to build on.
