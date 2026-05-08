# Sonoic Sonos Worker

Cloudflare Worker token broker for Sonos OAuth. It keeps the Sonos client secret
out of the iOS app and exposes the stable OAuth endpoints used by Sonoic.

## Routes

- `GET /healthz`
- `GET /oauth/sonos/callback`
- `POST /api/sonos/token`
- `POST /api/sonos/token/refresh`
- `POST /api/sonos/events`

## Configuration

Non-secret values live in `wrangler.jsonc`:

- `SONOS_CLIENT_ID`
- `SONOS_REDIRECT_URI`
- `SONOIC_APP_REDIRECT_URI`

The Sonos secret must be stored as a Cloudflare Worker secret:

```bash
npx wrangler secret put SONOS_CLIENT_SECRET
```

## Commands

```bash
npm install
npm test
npm run deploy
```

After deploy, verify:

```bash
curl https://sonos.ryvus.app/healthz
```
