# Security And Privacy

Sonoic is local-first, but it still handles network access, shared app state, artwork, and Apple platform identifiers. Keep those boundaries explicit.

## Current Boundaries

- Sonos control currently happens over the local network.
- Manual host configuration identifies a player on the user's LAN.
- Shared state and artwork are stored through the App Group path used by the app and widget.
- Bundle identifiers, App Group identifiers, signing, and entitlements are developer-account-specific.

## Rules

- Do not commit secrets, provisioning profiles, personal signing state, DerivedData, or local Xcode user state.
- Do not log private network details more broadly than needed for local debugging.
- Treat App Group identifier changes as architecture-affecting changes and document them in an execution plan.
- Keep local-network permission copy and behavior aligned with actual app behavior.
- Prefer typed or parsed Sonos responses over guessed response shapes.

## Review Checklist

- Did the change alter entitlements, App Groups, bundle identifiers, background modes, network behavior, or shared storage?
- Did the change add persistent logging, diagnostics, analytics, or external communication?
- Did the change introduce new files that might contain local machine state?
- Is any new security-sensitive behavior reflected in docs and PR notes?
