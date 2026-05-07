# Sonos OAuth Setup

Sonoic uses a Cloudflare Worker token broker so the iOS app never contains the
Sonos client secret. The app opens Sonos authorization, Sonos redirects to the
Worker, and the Worker redirects back into `sonoic://sonos-auth`.

## Worker

The Worker lives in:

```text
sonoic-sonos-worker/
```

Install dependencies when needed:

```bash
cd sonoic-sonos-worker
npm install
```

Set the Sonos secret in Cloudflare. Never commit it:

```bash
npx wrangler secret put SONOS_CLIENT_SECRET
```

Deploy:

```bash
npm run deploy
```

The Worker is routed to:

```text
https://sonos.ryvus.app
```

Health check:

```bash
curl https://sonos.ryvus.app/healthz
```

Expected response:

```json
{"ok":true}
```

## Sonos Developer Portal

Create a Control API integration and set:

```text
Redirect URI:
https://sonos.ryvus.app/oauth/sonos/callback

Event Callback URL:
https://sonos.ryvus.app/api/sonos/events
```

Save the credential after changing either URL.

## Xcode Build Settings

Create a local build-settings override:

```bash
cp Config/SonoicOAuth.local.example.xcconfig Config/SonoicOAuth.local.xcconfig
```

Then set the real Sonos key in `Config/SonoicOAuth.local.xcconfig`:

```text
SONOS_OAUTH_CLIENT_ID = <Sonos Key>
SONOS_OAUTH_REDIRECT_URI = https:/$(SONOIC_EMPTY)/sonos.ryvus.app/oauth/sonos/callback
SONOS_OAUTH_TOKEN_EXCHANGE_URL = https:/$(SONOIC_EMPTY)/sonos.ryvus.app/api/sonos/token
SONOS_OAUTH_TOKEN_REFRESH_URL = https:/$(SONOIC_EMPTY)/sonos.ryvus.app/api/sonos/token/refresh
```

Never put the Sonos Secret in Xcode, Info.plist, source control, or the iOS app.
`Config/SonoicOAuth.local.xcconfig` is ignored by git.
The `https:/$(SONOIC_EMPTY)/...` spelling is intentional: plain `https://...`
is parsed as `https:` because `//` starts a comment in `.xcconfig` files.

## Flow

1. Sonoic opens the Sonos authorization URL.
2. Sonos redirects to `/oauth/sonos/callback` on the Worker.
3. The Worker redirects back to `sonoic://sonos-auth` with the authorization code.
4. Sonoic posts the code to `/api/sonos/token`.
5. The Worker exchanges the real Sonos code with Sonos using the client secret.
6. Sonoic stores the returned token set in Keychain.
7. Sonoic verifies the token by reading households, groups, and players from the Sonos Control API.

## Local Broker

`scripts/sonos_token_broker.py` remains available for emergency local testing,
but the normal development and review path should use the Cloudflare Worker.
