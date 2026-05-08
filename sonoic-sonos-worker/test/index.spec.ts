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

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(302);
		const location = new URL(response.headers.get('location') ?? '');
		expect(location.protocol).toBe('sonoic:');
		expect(location.host).toBe('sonos-auth');
		expect(location.searchParams.get('state')).toBe('state-1');
		expect(location.searchParams.get('broker_code')).toBeTruthy();
		expect(location.searchParams.get('code')).toBeNull();
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

		const brokerCode = await makeBrokerCode('sonos-code', 'state-1');
		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				code: brokerCode,
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

	it('rejects replayed broker codes before calling Sonos again', async () => {
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

		const brokerCode = await makeBrokerCode('sonos-code', 'state-1');
		const localEnv = testEnv();
		const requestBody = {
			code: brokerCode,
			state: 'state-1',
			redirect_uri: env.SONOS_REDIRECT_URI,
		};
		const firstRequest = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(requestBody),
		});
		const secondRequest = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(requestBody),
		});
		const firstContext = createExecutionContext();
		const secondContext = createExecutionContext();

		const firstResponse = await worker.fetch(firstRequest, localEnv, firstContext);
		await waitOnExecutionContext(firstContext);
		const secondResponse = await worker.fetch(secondRequest, localEnv, secondContext);
		await waitOnExecutionContext(secondContext);

		expect(firstResponse.status).toBe(200);
		expect(secondResponse.status).toBe(400);
		await expect(secondResponse.json()).resolves.toMatchObject({ error: 'broker_code_redeemed' });
		expect(fetchMock).toHaveBeenCalledOnce();
	});

	it('releases broker code reservations when the Sonos exchange fails', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(
				new Response(JSON.stringify({ error: 'temporarily_unavailable' }), {
					status: 503,
					headers: { 'Content-Type': 'application/json' },
				}),
			)
			.mockResolvedValueOnce(
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

		const brokerCode = await makeBrokerCode('sonos-code', 'state-1');
		const localEnv = testEnv();
		const requestBody = {
			code: brokerCode,
			state: 'state-1',
			redirect_uri: env.SONOS_REDIRECT_URI,
		};
		const failedRequest = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(requestBody),
		});
		const retryRequest = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(requestBody),
		});
		const failedContext = createExecutionContext();
		const retryContext = createExecutionContext();

		const failedResponse = await worker.fetch(failedRequest, localEnv, failedContext);
		await waitOnExecutionContext(failedContext);
		const retryResponse = await worker.fetch(retryRequest, localEnv, retryContext);
		await waitOnExecutionContext(retryContext);

		expect(failedResponse.status).toBe(503);
		await expect(failedResponse.json()).resolves.toMatchObject({ error: 'sonos_error' });
		expect(retryResponse.status).toBe(200);
		await expect(retryResponse.json()).resolves.toMatchObject({
			access_token: 'access-1',
			refresh_token: 'refresh-1',
		});
		expect(fetchMock).toHaveBeenCalledTimes(2);
	});

	it('rejects raw authorization codes that were not issued by the worker', async () => {
		const fetchMock = vi.fn();
		vi.stubGlobal('fetch', fetchMock);

		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				code: 'raw-sonos-code',
				state: 'state-1',
				redirect_uri: env.SONOS_REDIRECT_URI,
			}),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({ error: 'invalid_broker_code' });
		expect(fetchMock).not.toHaveBeenCalled();
	});
});

function testEnv(): Env & { SONOS_CLIENT_SECRET: string } {
	return {
		...env,
		SONOS_CLIENT_SECRET: 'secret-1',
		SONOS_BROKER_CODE_REDEMPTIONS: makeRedemptionNamespace(),
	};
}

function makeRedemptionNamespace(): DurableObjectNamespace {
	type TestRedemptionRecord = { status: 'pending' | 'redeemed'; expiresAt: number };
	const redemptions = new Map<string, TestRedemptionRecord>();
	return {
		idFromName: () => ({}) as DurableObjectId,
		get: () =>
			({
				fetch: async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
					const body = JSON.parse(String(init?.body ?? '{}')) as { digest?: string; expires_at?: number };
					if (!body.digest) {
						return new Response(JSON.stringify({ error: 'missing_required_field:digest' }), { status: 400 });
					}

					const now = Math.floor(Date.now() / 1_000);
					for (const [digest, record] of redemptions) {
						if (record.expiresAt <= now) {
							redemptions.delete(digest);
						}
					}

					const path = new URL(String(input)).pathname;
					switch (path) {
						case '/reserve':
							if (redemptions.has(body.digest)) {
								return new Response(JSON.stringify({ error: 'broker_code_redeemed' }), { status: 409 });
							}

							redemptions.set(body.digest, { status: 'pending', expiresAt: body.expires_at ?? now });
							return new Response(JSON.stringify({ success: true }), { status: 201 });
						case '/complete': {
							const existing = redemptions.get(body.digest);
							if (!existing) {
								return new Response(JSON.stringify({ error: 'broker_code_not_reserved' }), { status: 409 });
							}

							redemptions.set(body.digest, { ...existing, status: 'redeemed' });
							return new Response(JSON.stringify({ success: true }), { status: 200 });
						}
						case '/release': {
							const existing = redemptions.get(body.digest);
							if (existing?.status === 'pending') {
								redemptions.delete(body.digest);
							}

							return new Response(JSON.stringify({ success: true }), { status: 200 });
						}
						default:
							return new Response(JSON.stringify({ error: 'not_found' }), { status: 404 });
					}
				},
			}) as DurableObjectStub,
	} as DurableObjectNamespace;
}

async function makeBrokerCode(code: string, state: string): Promise<string> {
	const payload = {
		code,
		state,
		expiresAt: Math.floor(Date.now() / 1_000) + 300,
	};
	const payloadPart = base64URLEncode(new TextEncoder().encode(JSON.stringify(payload)));
	const signaturePart = await hmacSignature(payloadPart);
	return `${payloadPart}.${signaturePart}`;
}

async function hmacSignature(value: string): Promise<string> {
	const key = await crypto.subtle.importKey('raw', new TextEncoder().encode('secret-1'), { name: 'HMAC', hash: 'SHA-256' }, false, [
		'sign',
	]);
	const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value));
	return base64URLEncode(new Uint8Array(signature));
}

function base64URLEncode(bytes: Uint8Array): string {
	let binary = '';
	for (const byte of bytes) {
		binary += String.fromCharCode(byte);
	}

	return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
