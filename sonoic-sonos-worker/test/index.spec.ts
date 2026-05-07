import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, describe, expect, it, vi } from 'vitest';
import worker from '../src/index';

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

describe('Sonos OAuth worker', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
	});

	it('redirects Sonos OAuth callbacks back into Sonoic', async () => {
		const request = new IncomingRequest(
			'https://sonos.ryvus.app/oauth/sonos/callback?state=state-1&code=sonos-code',
		);
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(302);
		expect(response.headers.get('location')).toBe('sonoic://sonos-auth?code=sonos-code&state=state-1');
		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('exchanges authorization codes with Sonos using worker secrets', async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			new Response(
				JSON.stringify({
					access_token: 'access-1',
					refresh_token: 'refresh-1',
					token_type: 'Bearer',
					expires_in: 3600,
				}),
				{ status: 200, headers: { 'Content-Type': 'application/json' } },
			),
		);
		vi.stubGlobal('fetch', fetchMock);

		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				code: 'sonos-code',
				state: 'state-1',
				redirect_uri: env.SONOS_REDIRECT_URI,
			}),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		await expect(response.json()).resolves.toMatchObject({
			access_token: 'access-1',
			refresh_token: 'refresh-1',
		});
		expect(fetchMock).toHaveBeenCalledOnce();
		const [url, options] = fetchMock.mock.calls[0];
		expect(url).toBe('https://api.sonos.com/login/v3/oauth/access');
		expect(options.method).toBe('POST');
		expect(options.headers.Authorization).toMatch(/^Basic /);
		expect(options.body.toString()).toBe(
			'grant_type=authorization_code&code=sonos-code&redirect_uri=https%3A%2F%2Fsonos.ryvus.app%2Foauth%2Fsonos%2Fcallback',
		);
	});
});

function testEnv(): Env & { SONOS_CLIENT_SECRET: string } {
	return {
		...env,
		SONOS_CLIENT_SECRET: 'secret-1',
	};
}
