# Sonos OAuth Local Development

Sonoic uses a tiny token broker during development so the iOS app never contains
the Sonos client secret.

## Start the Broker

Run this from the repo root, replacing the values with the Sonos developer
credentials and the current Cloudflare tunnel URL.

```bash
export SONOS_CLIENT_ID="<Sonos Key>"
export SONOS_CLIENT_SECRET="<Sonos Secret>"
export SONOS_REDIRECT_URI="https://<tunnel>.trycloudflare.com/oauth"
export SONOIC_APP_REDIRECT_URI="sonoic://sonos-auth"
python3 scripts/sonos_token_broker.py
```

The broker listens on `http://127.0.0.1:3000`.

## Start Cloudflare Tunnel

In a second terminal:

```bash
cloudflared tunnel --url http://127.0.0.1:3000
```

Use the HTTPS URL printed by Cloudflare everywhere below.

## Sonos Developer Portal

Set the redirect URI to:

```text
https://<tunnel>.trycloudflare.com/oauth
```

Set the event callback URL to:

```text
https://<tunnel>.trycloudflare.com/api/sonos/events
```

Save the client credential after changing either URL. If Sonos shows the generic
problem page after sign-in and the broker never logs `oauth callback received`,
Sonos failed before redirecting back to Sonoic. In that case, re-check that the
saved portal URLs exactly match the broker startup output, including path and no
trailing slash. The broker also accepts `/oauth/sonos/callback`, but `/oauth`
matches the official Sonos sample app and is the preferred development path.

## Xcode Build Settings

Create a local build-settings override:

```bash
cp Config/SonoicOAuth.local.example.xcconfig Config/SonoicOAuth.local.xcconfig
```

Then set these values in `Config/SonoicOAuth.local.xcconfig` for local
development:

```text
SONOS_OAUTH_CLIENT_ID = <Sonos Key>
SONOS_OAUTH_REDIRECT_URI = https:/$(SONOIC_EMPTY)/<tunnel>.trycloudflare.com/oauth
SONOS_OAUTH_TOKEN_EXCHANGE_URL = https:/$(SONOIC_EMPTY)/<tunnel>.trycloudflare.com/api/sonos/token
SONOS_OAUTH_TOKEN_REFRESH_URL = https:/$(SONOIC_EMPTY)/<tunnel>.trycloudflare.com/api/sonos/token/refresh
```

Never put the Sonos Secret in Xcode, Info.plist, source control, or the iOS app.
`Config/SonoicOAuth.local.xcconfig` is ignored by git.
The `https:/$(SONOIC_EMPTY)/...` spelling is intentional: plain `https://...`
is parsed as `https:` because `//` starts a comment in `.xcconfig` files.

## Flow

1. Sonoic opens the Sonos authorization URL.
2. Sonos redirects to `/oauth` on the broker.
3. The broker creates a short-lived one-time `broker_code`.
4. The broker redirects back to `sonoic://sonos-auth`.
5. Sonoic posts the `broker_code` to `/api/sonos/token`.
6. The broker exchanges the real Sonos code with Sonos using the client secret.
7. Sonoic stores the returned token set in Keychain.
