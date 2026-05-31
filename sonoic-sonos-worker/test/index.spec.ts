import { createExecutionContext, env, runInDurableObject, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, describe, expect, it, vi } from 'vitest';
import worker from '../src/index';

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

describe('Sonos OAuth worker', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
	});

	it('returns uncached health checks', async () => {
		const fetchMock = vi.fn();
		vi.stubGlobal('fetch', fetchMock);
		const request = new IncomingRequest('https://sonos.ryvus.app/healthz');
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		await expect(response.json()).resolves.toMatchObject({ ok: true });
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(fetchMock).not.toHaveBeenCalled();
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

	it('refreshes Sonos tokens with worker secrets', async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			new Response(
				JSON.stringify({
					access_token: 'access-2',
					refresh_token: 'refresh-2',
					token_type: 'Bearer',
					expires_in: 3600,
				}),
				{ status: 200, headers: { 'Content-Type': 'application/json' } },
			),
		);
		vi.stubGlobal('fetch', fetchMock);

		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token/refresh', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ refresh_token: 'refresh-1' }),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		await expect(response.json()).resolves.toMatchObject({
			access_token: 'access-2',
			refresh_token: 'refresh-2',
		});
		expect(fetchMock).toHaveBeenCalledOnce();
		const [url, options] = fetchMock.mock.calls[0];
		expect(url).toBe('https://api.sonos.com/login/v3/oauth/access');
		expect(options.method).toBe('POST');
		expect(options.headers.Authorization).toMatch(/^Basic /);
		expect(options.body.toString()).toBe('grant_type=refresh_token&refresh_token=refresh-1');
	});

	it('redacts upstream token refresh error bodies', async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			new Response('<html>refresh-token-secret should not echo</html>', {
				status: 401,
				headers: { 'Content-Type': 'text/html' },
			}),
		);
		vi.stubGlobal('fetch', fetchMock);

		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token/refresh', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ refresh_token: 'refresh-token-secret' }),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);
		const body = (await response.json()) as Record<string, unknown>;

		expect(response.status).toBe(401);
		expect(body).toMatchObject({ error: 'sonos_error', status: 401 });
		expect(body.detail).toBeUndefined();
		expect(JSON.stringify(body)).not.toContain('refresh-token-secret');
		expect(fetchMock).toHaveBeenCalledOnce();
	});

	it('signs broker codes with a dedicated signing secret when configured', async () => {
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

		const localEnv = testEnv({ brokerCodeSigningSecret: 'broker-secret-1' });
		const callbackRequest = new IncomingRequest(
			'https://sonos.ryvus.app/oauth/sonos/callback?state=state-1&code=sonos-code',
		);
		const callbackContext = createExecutionContext();
		const callbackResponse = await worker.fetch(callbackRequest, localEnv, callbackContext);
		await waitOnExecutionContext(callbackContext);
		const location = new URL(callbackResponse.headers.get('location') ?? '');
		const brokerCode = location.searchParams.get('broker_code');
		const tokenRequest = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				code: brokerCode,
				state: 'state-1',
				redirect_uri: env.SONOS_REDIRECT_URI,
			}),
		});
		const tokenContext = createExecutionContext();

		const response = await worker.fetch(tokenRequest, localEnv, tokenContext);
		await waitOnExecutionContext(tokenContext);

		expect(response.status).toBe(200);
		await expect(response.json()).resolves.toMatchObject({
			access_token: 'access-1',
			refresh_token: 'refresh-1',
		});
		expect(fetchMock).toHaveBeenCalledOnce();
	});

	it('rejects client-secret signed broker codes when a dedicated signing secret is configured', async () => {
		const fetchMock = vi.fn();
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

		const response = await worker.fetch(request, testEnv({ brokerCodeSigningSecret: 'broker-secret-1' }), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({ error: 'invalid_broker_code' });
		expect(fetchMock).not.toHaveBeenCalled();
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

	it('rejects oversized JSON bodies from content length before parsing', async () => {
		const fetchMock = vi.fn();
		vi.stubGlobal('fetch', fetchMock);
		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token/refresh', {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'Content-Length': String(1024 * 1024 + 1),
			},
			body: JSON.stringify({ refresh_token: 'refresh-1' }),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(413);
		await expect(response.json()).resolves.toMatchObject({ error: 'request_body_too_large' });
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it('rejects oversized JSON bodies after measuring the actual body bytes', async () => {
		const fetchMock = vi.fn();
		vi.stubGlobal('fetch', fetchMock);
		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/token/refresh', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ refresh_token: 'x'.repeat(1024 * 1024) }),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(413);
		await expect(response.json()).resolves.toMatchObject({ error: 'request_body_too_large' });
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it('accepts Sonos event callbacks as an intentional no-op', async () => {
		const fetchMock = vi.fn();
		vi.stubGlobal('fetch', fetchMock);
		const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/events', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ event: 'ignored' }),
		});
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(202);
		await expect(response.json()).resolves.toMatchObject({ success: true });
		expect(response.headers.get('cache-control')).toBe('no-store');
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

	it('schedules cloud queue pruning outside normal request handling', async () => {
		const createResponse = await createCloudQueue({ startItemId: 'sonoic-track-2' });
		const stub = cloudQueuesStub();

		const alarmAt = await runInDurableObject(stub, async (_instance, state) => state.storage.getAlarm());

		expect(createResponse.queueId).toEqual(expect.any(String));
		expect(alarmAt).toEqual(expect.any(Number));
	});

	it('returns the queue start item as the default item window playhead', async () => {
		const createResponse = await createCloudQueue({ startItemId: 'sonoic-track-2' });
		const queueBaseUrl = String(createResponse.queueBaseUrl);
		const request = new IncomingRequest(`${queueBaseUrl}/itemWindow?upcomingWindowSize=2`);
		const ctx = createExecutionContext();

		const response = await worker.fetch(request, testEnv(), ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		const body = (await response.json()) as Record<string, unknown>;
		expect(body.windowPlayhead).toMatchObject({ itemId: 'sonoic-track-2', positionMillis: 0 });
		expect(body.items).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ id: 'sonoic-track-2' }),
				expect.objectContaining({ id: 'sonoic-track-3' }),
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

	it.each([
		{
			name: 'without an item id',
			mutate: (body: Record<string, unknown>) => {
				const firstItem = cloudQueueItem(body, 0);
				delete firstItem.id;
			},
			error: 'cloud_queue_item_missing_id:0',
		},
		{
			name: 'with an overlong item id',
			mutate: (body: Record<string, unknown>) => {
				cloudQueueItem(body, 0).id = 'x'.repeat(129);
			},
			error: 'cloud_queue_item_id_too_long:0',
		},
		{
			name: 'with duplicate item ids',
			mutate: (body: Record<string, unknown>) => {
				cloudQueueItem(body, 1).id = cloudQueueItem(body, 0).id;
			},
			error: 'cloud_queue_item_ids_must_be_unique',
		},
		{
			name: 'without a track object',
			mutate: (body: Record<string, unknown>) => {
				const firstItem = cloudQueueItem(body, 0);
				delete firstItem.track;
			},
			error: 'cloud_queue_item_missing_track:0',
		},
		{
			name: 'without track content type',
			mutate: (body: Record<string, unknown>) => {
				const firstTrack = cloudQueueTrack(body, 0);
				delete firstTrack.contentType;
			},
			error: 'cloud_queue_item_invalid_track:0',
		},
		{
			name: 'without a track playback reference',
			mutate: (body: Record<string, unknown>) => {
				const firstTrack = cloudQueueTrack(body, 0);
				delete firstTrack.id;
				delete firstTrack.mediaUrl;
			},
			error: 'cloud_queue_item_invalid_track:0',
		},
	])('rejects cloud queue items $name', async ({ mutate, error }) => {
		stubSuccessfulSonosTokenValidation();
		const body = cloudQueueBody();
		mutate(body);

		const response = await createCloudQueueFromBody(body);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({ error });
	});

	it.each([
		{
			name: 'container name',
			mutate: (body: Record<string, unknown>) => {
				const container = body.container as Record<string, unknown>;
				container.name = overlongCloudQueueString();
			},
			error: 'cloud_queue_string_too_long:container.name',
		},
		{
			name: 'track name',
			mutate: (body: Record<string, unknown>) => {
				cloudQueueTrack(body, 0).name = overlongCloudQueueString();
			},
			error: 'cloud_queue_string_too_long:items.0.track.name',
		},
		{
			name: 'nested track artist name',
			mutate: (body: Record<string, unknown>) => {
				const artist = cloudQueueTrack(body, 0).artist as Record<string, unknown>;
				artist.name = overlongCloudQueueString();
			},
			error: 'cloud_queue_string_too_long:items.0.track.artist.name',
		},
	])('rejects cloud queue payloads with overlong $name', async ({ mutate, error }) => {
		stubSuccessfulSonosTokenValidation();
		const body = cloudQueueBody();
		mutate(body);

		const response = await createCloudQueueFromBody(body);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({ error });
	});

	it.each([
		{
			name: 'container image URL',
			mutate: (body: Record<string, unknown>) => {
				const container = body.container as Record<string, unknown>;
				container.imageUrl = 'javascript:alert(1)';
			},
			error: 'cloud_queue_url_invalid:container.imageUrl',
		},
		{
			name: 'track media URL',
			mutate: (body: Record<string, unknown>) => {
				cloudQueueTrack(body, 0).mediaUrl = 'file:///tmp/track.m4a';
			},
			error: 'cloud_queue_url_invalid:items.0.track.mediaUrl',
		},
		{
			name: 'nested service image URL',
			mutate: (body: Record<string, unknown>) => {
				const service = cloudQueueTrack(body, 0).service as Record<string, unknown>;
				service.imageUrl = 'ftp://example.com/service.png';
			},
			error: 'cloud_queue_url_invalid:items.0.track.service.imageUrl',
		},
	])('rejects cloud queue payloads with invalid $name', async ({ mutate, error }) => {
		stubSuccessfulSonosTokenValidation();
		const body = cloudQueueBody();
		mutate(body);

		const response = await createCloudQueueFromBody(body);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({ error });
	});
});

function testEnv(options: { brokerCodeSigningSecret?: string } = {}): Env & {
	SONOS_CLIENT_SECRET: string;
	BROKER_CODE_SIGNING_SECRET?: string;
} {
	return {
		...env,
		SONOS_CLIENT_SECRET: 'secret-1',
		BROKER_CODE_SIGNING_SECRET: options.brokerCodeSigningSecret,
		SONOS_BROKER_CODE_REDEMPTIONS: makeRedemptionNamespace(),
	};
}

async function createCloudQueue(options: { startItemId?: string } = {}): Promise<Record<string, unknown>> {
	stubSuccessfulSonosTokenValidation();
	const response = await createCloudQueueFromBody(cloudQueueBody(options));
	expect(response.status).toBe(201);
	return (await response.json()) as Record<string, unknown>;
}

async function createCloudQueueFromBody(body: Record<string, unknown>): Promise<Response> {
	const request = new IncomingRequest('https://sonos.ryvus.app/api/sonos/cloud-queues', {
		method: 'POST',
		headers: authenticatedCloudQueueHeaders(),
		body: JSON.stringify(body),
	});
	const ctx = createExecutionContext();
	const response = await worker.fetch(request, testEnv(), ctx);
	await waitOnExecutionContext(ctx);
	return response;
}

function authenticatedCloudQueueHeaders(): HeadersInit {
	return {
		'Content-Type': 'application/json',
		Authorization: 'Bearer access-1',
	};
}

function cloudQueuesStub(): DurableObjectStub {
	const namespace = env.SONOIC_CLOUD_QUEUES;
	return namespace.get(namespace.idFromName('global'));
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

function cloudQueueItem(body: Record<string, unknown>, index: number): Record<string, unknown> {
	const items = body.items as Record<string, unknown>[];
	return items[index];
}

function cloudQueueTrack(body: Record<string, unknown>, index: number): Record<string, unknown> {
	return cloudQueueItem(body, index).track as Record<string, unknown>;
}

function overlongCloudQueueString(): string {
	return 'x'.repeat(4097);
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
