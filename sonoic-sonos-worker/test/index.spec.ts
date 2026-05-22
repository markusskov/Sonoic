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

describe('Sonoic Cloud Queue worker', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
	});

	it('rejects unauthenticated cloud queue creation', async () => {
		const fetchMock = vi.fn();
		vi.stubGlobal('fetch', fetchMock);

		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/cloud-queues', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(cloudQueueBody()),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(401);
		await expect(response.json()).resolves.toMatchObject({ error: 'missing_authorization' });
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it('creates a seekable cloud queue with the requested start item id', async () => {
		const fetchMock = stubSuccessfulSonosTokenValidation();
		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/cloud-queues', {
			method: 'POST',
			headers: authenticatedCloudQueueHeaders(),
			body: JSON.stringify(cloudQueueBody({ startItemId: 'sonoic-track-2' })),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(201);
		const body = (await response.json()) as Record<string, unknown>;
		expect(body.queueId).toEqual(expect.any(String));
		expect(body.queueBaseUrl).toContain('https://sonos.ryvus.app');
		expect(body.queueBaseUrl).toContain(`/cloud-queues/${body.queueId}/v2.3`);
		expect(body.startItemId).toBe('sonoic-track-2');
		expect(body.trackMetadata).toMatchObject({ name: 'Track 2' });
		expect(fetchMock).toHaveBeenCalledWith(
			'https://api.ws.sonos.com/control/api/v1/households',
			expect.objectContaining({
				method: 'GET',
				headers: expect.objectContaining({ Authorization: 'Bearer access-1' }),
			}),
		);
	});

	it('returns the first queue item as the default item window playhead', async () => {
		const createResponse = await createCloudQueue({ startItemId: 'sonoic-track-2' });
		const queueBaseUrl = String(createResponse.queueBaseUrl);
		const request = new IncomingRequest(`${queueBaseUrl}/itemWindow?upcomingWindowSize=2`);
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		const body = (await response.json()) as Record<string, unknown>;
		expect(body.windowPlayhead).toMatchObject({ itemId: 'sonoic-track-1', positionMillis: 0 });
		expect(body.items).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ id: 'sonoic-track-1' }),
				expect.objectContaining({ id: 'sonoic-track-2' }),
			]),
		);
	});

	it('returns requested cloud queue item ids unchanged for seek status mapping', async () => {
		const createResponse = await createCloudQueue({ startItemId: 'sonoic-track-2' });
		const queueBaseUrl = String(createResponse.queueBaseUrl);
		const request = new IncomingRequest(`${queueBaseUrl}/itemWindow?itemId=sonoic-track-2&previousWindowSize=1&upcomingWindowSize=1`);
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		const body = (await response.json()) as Record<string, unknown>;
		expect(body.windowPlayhead).toMatchObject({ itemId: 'sonoic-track-2', positionMillis: 0 });
		expect(body.items).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ id: 'sonoic-track-1' }),
				expect.objectContaining({ id: 'sonoic-track-2' }),
				expect.objectContaining({ id: 'sonoic-track-3' }),
			]),
		);
	});

	it('rejects track items without a content type', async () => {
		stubSuccessfulSonosTokenValidation();
		const body = cloudQueueBody();
		const firstItem = body.items[0] as Record<string, unknown>;
		const firstTrack = firstItem.track as Record<string, unknown>;
		delete firstTrack.contentType;
		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/cloud-queues', {
			method: 'POST',
			headers: authenticatedCloudQueueHeaders(),
			body: JSON.stringify(body),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({ error: 'cloud_queue_item_invalid_track:0' });
	});
});

function testEnv(): Env & { SONOS_CLIENT_SECRET: string } {
	return {
		...env,
		SONOS_CLIENT_SECRET: 'secret-1',
		SONOS_BROKER_CODE_REDEMPTIONS: makeRedemptionNamespace(),
	};
}

async function createCloudQueue(options: { startItemId?: string } = {}): Promise<Record<string, unknown>> {
	stubSuccessfulSonosTokenValidation();
	const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/cloud-queues', {
		method: 'POST',
		headers: authenticatedCloudQueueHeaders(),
		body: JSON.stringify(cloudQueueBody(options)),
	});
	const ctx = createExecutionContext();
	const response = await worker.fetch(request, testEnv(), ctx);
	await waitOnExecutionContext(ctx);
	expect(response.status).toBe(201);
	return (await response.json()) as Record<string, unknown>;
}

function authenticatedCloudQueueHeaders(): HeadersInit {
	return {
		'Content-Type': 'application/json',
		Authorization: 'Bearer access-1',
	};
}

function stubSuccessfulSonosTokenValidation(): ReturnType<typeof vi.fn> {
	const fetchMock = vi.fn().mockResolvedValue(
		new Response(JSON.stringify({ households: [{ id: 'household-1' }] }), {
			status: 200,
			headers: { 'Content-Type': 'application/json' },
		}),
	);
	vi.stubGlobal('fetch', fetchMock);
	return fetchMock;
}

function cloudQueueBody(options: { startItemId?: string } = {}): Record<string, unknown> {
	return {
		container: {
			id: { serviceId: '204', objectId: 'libraryplaylist:playlist-1' },
			name: 'Playlist 1',
			type: 'playlist',
			service: { id: '204', name: 'Apple Music' },
			playbackPolicies: { canSeek: true },
		},
		items: [1, 2, 3].map((number) => ({
			id: `sonoic-track-${number}`,
			track: {
				id: { serviceId: '204', objectId: `librarytrack:track-${number}` },
				name: `Track ${number}`,
				contentType: 'application/vnd.apple.mpegurl',
				artist: { name: 'Artist' },
				album: { name: 'Album' },
				durationMillis: 180_000,
				service: { id: '204', name: 'Apple Music' },
			},
			playbackPolicies: { canSeek: true },
		})),
		startItemId: options.startItemId,
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
