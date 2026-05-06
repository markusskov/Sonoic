# Execution Plan: Sonoic Plus Foundation

## Goal

Add a small RevenueCat-backed Sonoic Plus foundation that can support tasteful personalization features without gating core Sonos control.

## Scope

- Add RevenueCat as the purchase/paywall provider.
- Add a Sonoic-owned Plus entitlement state and feature list.
- Add Settings entry points for a Plus status/paywall surface.
- Keep all existing playback, discovery, queue, room, Lock Screen, and Apple Music behavior free and unchanged.
- Save the remaining modernization/refactor backlog so future cleanup stays explicit.

Out of scope:

- Implementing Home section ordering, extra widgets, room presets, or alternate app icons.
- Custom App Store product setup beyond code hooks and documented identifiers.
- Paywall design work beyond using RevenueCat's provided surface.

## Acceptance Criteria

- Sonoic builds when RevenueCat is configured with a public SDK key.
- Sonoic also has a clear not-configured state while the key is absent.
- Settings shows a quiet Sonoic Plus entry without disrupting normal settings.
- Existing free functionality remains ungated.
- Remaining refactor work is tracked in `docs/exec-plans/tech-debt-tracker.md`.

## Context

- [README.md](../../../README.md)
- [plan.md](../../../plan.md)
- [ARCHITECTURE.md](../../../ARCHITECTURE.md)
- [Agent harness](../../agent-harness.md)
- RevenueCat iOS installation: <https://www.revenuecat.com/docs/getting-started/installation/ios>
- RevenueCat SDK configuration: <https://www.revenuecat.com/docs/getting-started/configuring-sdk>
- RevenueCat paywalls: <https://www.revenuecat.com/docs/tools/paywalls/displaying-paywalls>

## Plan

- [x] Create execution plan and save refactor follow-ups.
- [x] Add RevenueCat package dependency.
- [x] Add Plus state, feature model, and controller.
- [x] Wire Plus refresh/configuration through `SonoicModel`.
- [x] Add Settings Plus row and detail/paywall surface.
- [x] Run harness and iOS build.
- [ ] Open PR and address review feedback.

## Validation

- [x] `python3 scripts/agent_harness_check.py`
- [x] `xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] Manual check: Settings opens Plus screen and existing playback path is unchanged.

## Decision Log

- 2026-05-04: Core Sonos control remains free. Plus starts as support/personalization infrastructure.
- 2026-05-04: Use RevenueCat/RevenueCatUI, but keep app code behind Sonoic-owned types.

## Progress

- 2026-05-04: Started implementation on `sonoic/plus-foundation`.
- 2026-05-04: Added RevenueCat/RevenueCatUI package wiring, Plus state/controller, and Settings paywall surface.
