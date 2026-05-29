const SONOS_TOKEN_URL = 'https://api.sonos.com/login/v3/oauth/access';
const SONOS_CONTROL_API_BASE_URL = 'https://api.ws.sonos.com/control/api/v1';
const OAUTH_CALLBACK_PATHS = new Set(['/oauth/sonos/callback', '/oauth']);
const BROKER_CODE_TTL_SECONDS = 5 * 60;
const BROKER_CODE_STORAGE_PREFIX = 'broker-code:';
const BROKER_CODE_PRUNE_GRACE_SECONDS = 60;
const CLOUD_QUEUE_API_VERSION = 'v2.3';
const CLOUD_QUEUE_STORAGE_PREFIX = 'cloud-queue:';
const CLOUD_QUEUE_TTL_SECONDS = 24 * 60 * 60;
const CLOUD_QUEUE_PRUNE_GRACE_SECONDS = 60;
const CLOUD_QUEUE_MAX_WINDOW_ITEMS = 20;
const EXTERNAL_ORIGIN_HEADER = 'X-Sonoic-External-Origin';
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

type WorkerEnv = Env & {
	SONOS_CLIENT_SECRET?: string;
	SONOS_BROKER_CODE_REDEMPTIONS?: DurableObjectNamespace;
	SONOIC_CLOUD_QUEUES?: DurableObjectNamespace;
};

type JsonObject = Record<string, unknown>;

type BrokerCodePayload = {
	code: string;
	state: string;
	expiresAt: number;
};

type BrokerCodeRedemptionRecord = {
	status: 'pending' | 'redeemed';
	expiresAt: number;
};

type CloudQueueRecord = {
	queueId: string;
	contextVersion: string;
	queueVersion: string;
	container: JsonObject;
	items: JsonObject[];
	startItemId: string;
	createdAt: number;
	expiresAt: number;
};

class HTTPError extends Error {
	constructor(
		readonly status: number,
		message: string,
		readonly body?: JsonObject,
	) {
		super(message);
	}
}

export class BrokerCodeRedemptions {
	constructor(private readonly state: DurableObjectState) {}

	async fetch(request: Request): Promise<Response> {
		if (request.method !== 'POST') {
			return jsonResponse(405, { error: 'method_not_allowed' });
		}

		const body = await readJson(request);
		const digest = requiredString(body, 'digest');
		await this.pruneExpiredRedemptions();
		const storageKey = `${BROKER_CODE_STORAGE_PREFIX}${digest}`;

		const url = new URL(request.url);
		switch (url.pathname) {
			case '/reserve':
				return await this.reserve(storageKey, body);
			case '/complete':
				return await this.complete(storageKey);
			case '/release':
				return await this.release(storageKey);
			default:
				return jsonResponse(404, { error: 'not_found' });
		}
	}

	private async reserve(storageKey: string, body: JsonObject): Promise<Response> {
		const existing = await this.state.storage.get(storageKey);
		if (existing !== undefined) {
			return jsonResponse(409, { error: 'broker_code_redeemed' });
		}

		const expiresAt = requiredNumber(body, 'expires_at');
		await this.state.storage.put(storageKey, { status: 'pending', expiresAt } satisfies BrokerCodeRedemptionRecord);
		await this.schedulePrune(expiresAt);
		return jsonResponse(201, { success: true });
	}

	private async complete(storageKey: string): Promise<Response> {
		const existing = await this.state.storage.get<BrokerCodeRedemptionRecord>(storageKey);
		if (!existing) {
			return jsonResponse(409, { error: 'broker_code_not_reserved' });
		}

		await this.state.storage.put(storageKey, { ...existing, status: 'redeemed' } satisfies BrokerCodeRedemptionRecord);
		return jsonResponse(200, { success: true });
	}

	private async release(storageKey: string): Promise<Response> {
		const existing = await this.state.storage.get<BrokerCodeRedemptionRecord>(storageKey);
		if (existing?.status === 'pending') {
			await this.state.storage.delete(storageKey);
		}

		return jsonResponse(200, { success: true });
	}

	async alarm(): Promise<void> {
		await this.pruneExpiredRedemptions();
		await this.scheduleNextStoredExpiration();
	}

	private async pruneExpiredRedemptions(): Promise<void> {
		const now = currentEpochSeconds();
		const entries = await this.state.storage.list<BrokerCodeRedemptionRecord>({ prefix: BROKER_CODE_STORAGE_PREFIX });
		const expiredKeys = [...entries]
			.filter(([, record]) => record.expiresAt <= now)
			.map(([key]) => key);

		await Promise.all(expiredKeys.map((key) => this.state.storage.delete(key)));
	}

	private async schedulePrune(expiresAt: number): Promise<void> {
		const alarmAt = (expiresAt + BROKER_CODE_PRUNE_GRACE_SECONDS) * 1_000;
		const currentAlarm = await this.state.storage.getAlarm();
		if (currentAlarm === null || alarmAt < currentAlarm) {
			await this.state.storage.setAlarm(alarmAt);
		}
	}

	private async scheduleNextStoredExpiration(): Promise<void> {
		const entries = await this.state.storage.list<BrokerCodeRedemptionRecord>({ prefix: BROKER_CODE_STORAGE_PREFIX });
		const nextExpiration = [...entries].reduce<number | undefined>((next, [, record]) => {
			if (next === undefined || record.expiresAt < next) {
				return record.expiresAt;
			}

			return next;
		}, undefined);

		if (nextExpiration !== undefined) {
			await this.schedulePrune(nextExpiration);
		}
	}
}

export class SonoicCloudQueues {
	constructor(private readonly state: DurableObjectState) {}

	async fetch(request: Request): Promise<Response> {
		const url = new URL(request.url);
		try {
			if (request.method === 'POST' && url.pathname === '/create') {
				return await this.createQueue(request);
			}

			if (request.method === 'GET') {
				return await this.handleQueueRead(url);
			}

			return jsonResponse(405, { error: 'method_not_allowed' });
		} catch (error) {
			if (error instanceof HTTPError) {
				return jsonResponse(error.status, error.body ?? { error: error.message });
			}

			return jsonResponse(500, { error: 'cloud_queue_error' });
		}
	}

	private async createQueue(request: Request): Promise<Response> {
		const body = await readJson(request);
		const container = requiredObject(body, 'container');
		const items = requiredObjectArray(body, 'items');
		if (items.length === 0) {
			throw new HTTPError(400, 'cloud_queue_requires_items');
		}

		const itemIDs = items.map((item, index) => validateCloudQueueItem(item, index));
		const uniqueItemIDs = new Set(itemIDs);
		if (uniqueItemIDs.size !== itemIDs.length) {
			throw new HTTPError(400, 'cloud_queue_item_ids_must_be_unique');
		}

		const requestedStartItemID = optionalString(body, 'startItemId');
		const startItemId = requestedStartItemID && uniqueItemIDs.has(requestedStartItemID)
			? requestedStartItemID
			: itemIDs[0];
		const queueId = crypto.randomUUID();
		const now = currentEpochSeconds();
		const record: CloudQueueRecord = {
			queueId,
			contextVersion: `CV:${now}:${queueId}`,
			queueVersion: `QV:${now}:${queueId}`,
			container,
			items,
			startItemId,
			createdAt: now,
			expiresAt: now + CLOUD_QUEUE_TTL_SECONDS,
		};

		await this.state.storage.put(`${CLOUD_QUEUE_STORAGE_PREFIX}${queueId}`, record);
		await this.schedulePrune(record.expiresAt);
		const queueBaseUrl = `${externalOrigin(request)}/cloud-queues/${queueId}/${CLOUD_QUEUE_API_VERSION}`;
		const startItem = items.find((item) => item.id === startItemId) ?? items[0];
		const responseBody: JsonObject = {
			queueId,
			queueBaseUrl,
			contextVersion: record.contextVersion,
			queueVersion: record.queueVersion,
			startItemId,
		};
		if (isJsonObject(startItem.track)) {
			responseBody.trackMetadata = startItem.track;
		}

		return jsonResponse(201, responseBody);
	}

	private async handleQueueRead(url: URL): Promise<Response> {
		const match = /^\/cloud-queues\/([^/]+)\/([^/]+)\/([^/]+)$/.exec(url.pathname);
		if (!match) {
			return jsonResponse(404, { error: 'not_found' });
		}

		const [, queueId, apiVersion, operation] = match;
		if (apiVersion !== CLOUD_QUEUE_API_VERSION) {
			throw new HTTPError(404, 'unsupported_cloud_queue_version');
		}

		const record = await this.readQueueRecord(queueId);
		switch (operation) {
			case 'context':
				return jsonResponse(200, this.contextResponse(record));
			case 'version':
				return jsonResponse(200, {
					contextVersion: record.contextVersion,
					queueVersion: record.queueVersion,
				});
			case 'itemWindow':
				return jsonResponse(200, this.itemWindowResponse(record, url.searchParams));
			default:
				return jsonResponse(404, { error: 'not_found' });
		}
	}

	private async readQueueRecord(queueId: string): Promise<CloudQueueRecord> {
		const record = await this.state.storage.get<CloudQueueRecord>(`${CLOUD_QUEUE_STORAGE_PREFIX}${queueId}`);
		if (!record || record.expiresAt <= currentEpochSeconds()) {
			throw new HTTPError(404, 'cloud_queue_not_found');
		}

		return record;
	}

	async alarm(): Promise<void> {
		await this.pruneExpiredQueues();
		await this.scheduleNextStoredExpiration();
	}

	private contextResponse(record: CloudQueueRecord): JsonObject {
		return {
			contextVersion: record.contextVersion,
			queueVersion: record.queueVersion,
			container: record.container,
			playbackPolicies: {
				canSkip: true,
				canSkipBack: true,
				canSeek: true,
				canSkipToItem: true,
				canShuffle: true,
			},
		};
	}

	private itemWindowResponse(record: CloudQueueRecord, searchParams: URLSearchParams): JsonObject {
		const requestedItemID = searchParams.get('itemId') || record.startItemId || optionalString(record.items[0] ?? {}, 'id');
		const targetIndex = record.items.findIndex((item) => item.id === requestedItemID);
		if (targetIndex < 0) {
			throw new HTTPError(404, 'cloud_queue_item_not_found');
		}

		const previousWindowSize = clampedWindowSize(searchParams.get('previousWindowSize'), 0);
		const upcomingWindowSize = clampedWindowSize(searchParams.get('upcomingWindowSize'), CLOUD_QUEUE_MAX_WINDOW_ITEMS - 1);
		let startIndex = Math.max(0, targetIndex - previousWindowSize);
		let endIndex = Math.min(record.items.length, targetIndex + upcomingWindowSize + 1);

		if (endIndex - startIndex > CLOUD_QUEUE_MAX_WINDOW_ITEMS) {
			const overflow = endIndex - startIndex - CLOUD_QUEUE_MAX_WINDOW_ITEMS;
			if (targetIndex - startIndex >= endIndex - targetIndex - 1) {
				startIndex += overflow;
			} else {
				endIndex -= overflow;
			}
		}

		return {
			contextVersion: record.contextVersion,
			queueVersion: record.queueVersion,
			includesBeginningOfQueue: startIndex === 0,
			includesEndOfQueue: endIndex >= record.items.length,
			items: record.items.slice(startIndex, endIndex),
			windowPlayhead: {
				itemId: requestedItemID,
				positionMillis: 0,
			},
		};
	}

	private async pruneExpiredQueues(): Promise<void> {
		const now = currentEpochSeconds();
		const entries = await this.state.storage.list<CloudQueueRecord>({ prefix: CLOUD_QUEUE_STORAGE_PREFIX });
		const expiredKeys = [...entries]
			.filter(([, record]) => record.expiresAt <= now)
			.map(([key]) => key);

		await Promise.all(expiredKeys.map((key) => this.state.storage.delete(key)));
	}

	private async schedulePrune(expiresAt: number): Promise<void> {
		const alarmAt = (expiresAt + CLOUD_QUEUE_PRUNE_GRACE_SECONDS) * 1_000;
		const currentAlarm = await this.state.storage.getAlarm();
		if (currentAlarm === null || alarmAt < currentAlarm) {
			await this.state.storage.setAlarm(alarmAt);
		}
	}

	private async scheduleNextStoredExpiration(): Promise<void> {
		const entries = await this.state.storage.list<CloudQueueRecord>({ prefix: CLOUD_QUEUE_STORAGE_PREFIX });
		const nextExpiration = [...entries].reduce<number | undefined>((next, [, record]) => {
			if (next === undefined || record.expiresAt < next) {
				return record.expiresAt;
			}

			return next;
		}, undefined);

		if (nextExpiration !== undefined) {
			await this.schedulePrune(nextExpiration);
		}
	}
}

export default {
	async fetch(request, env): Promise<Response> {
		try {
			const url = new URL(request.url);
			if (request.method === 'GET' && url.pathname === '/healthz') {
				return jsonResponse(200, { ok: true });
			}

			if (request.method === 'GET' && OAUTH_CALLBACK_PATHS.has(url.pathname)) {
				return await handleOAuthCallback(url, env as WorkerEnv);
			}

			if (request.method === 'POST' && url.pathname === '/api/sonos/token') {
				return await handleTokenExchange(request, env as WorkerEnv);
			}

			if (request.method === 'POST' && url.pathname === '/api/sonos/token/refresh') {
				return await handleTokenRefresh(request, env as WorkerEnv);
			}

			if (request.method === 'POST' && url.pathname === '/api/sonos/events') {
				return jsonResponse(202, { success: true });
			}

			if (request.method === 'POST' && url.pathname === '/api/sonos/cloud-queues') {
				return await handleCreateCloudQueue(request, env as WorkerEnv);
			}

			if (request.method === 'GET' && url.pathname.startsWith('/cloud-queues/')) {
				return await handleCloudQueueRead(request, env as WorkerEnv);
			}

			return jsonResponse(404, { error: 'not_found' });
		} catch (error) {
			if (error instanceof HTTPError) {
				return jsonResponse(error.status, error.body ?? { error: error.message });
			}

			return jsonResponse(500, { error: 'broker_error' });
		}
	},
} satisfies ExportedHandler<Env>;

async function handleCreateCloudQueue(request: Request, env: WorkerEnv): Promise<Response> {
	const accessToken = requireBearerAccessToken(request);
	await validateSonosAccessToken(accessToken);
	return await callSonoicCloudQueues(env, '/create', request);
}

async function handleCloudQueueRead(request: Request, env: WorkerEnv): Promise<Response> {
	const url = new URL(request.url);
	return await callSonoicCloudQueues(env, `${url.pathname}${url.search}`, request);
}

async function handleOAuthCallback(url: URL, env: WorkerEnv): Promise<Response> {
	const state = url.searchParams.get('state') ?? '';
	const sonosError = url.searchParams.get('error');
	if (sonosError) {
		return redirectToApp(env, {
			error: sonosError,
			error_description: url.searchParams.get('error_description') ?? sonosError,
			state,
		});
	}

	const code = url.searchParams.get('code');
	if (!code || !state) {
		return redirectToApp(env, {
			error: 'missing_code_or_state',
			state,
		});
	}

	const brokerCode = await makeBrokerCode(env, { code, state, expiresAt: currentEpochSeconds() + BROKER_CODE_TTL_SECONDS });
	return redirectToApp(env, { broker_code: brokerCode, state });
}

async function handleTokenExchange(request: Request, env: WorkerEnv): Promise<Response> {
	const body = await readJson(request);
	const brokerCode = requiredString(body, 'code');
	const state = requiredString(body, 'state');
	const redirectURI = requiredString(body, 'redirect_uri');
	validateRedirectURI(env, redirectURI);
	const payload = await readBrokerCode(env, brokerCode, state);
	await reserveBrokerCodeRedemption(env, brokerCode, payload.expiresAt);

	let tokenResponse: JsonObject;
	try {
		tokenResponse = await requestSonosToken(env, {
			grant_type: 'authorization_code',
			code: payload.code,
			redirect_uri: redirectURI,
		});
	} catch (error) {
		await releaseBrokerCodeRedemption(env, brokerCode);
		throw error;
	}

	await completeBrokerCodeRedemption(env, brokerCode);
	return jsonResponse(200, tokenResponse);
}

async function handleTokenRefresh(request: Request, env: WorkerEnv): Promise<Response> {
	const body = await readJson(request);
	const refreshToken = requiredString(body, 'refresh_token');

	const tokenResponse = await requestSonosToken(env, {
		grant_type: 'refresh_token',
		refresh_token: refreshToken,
	});
	return jsonResponse(200, tokenResponse);
}

async function requestSonosToken(env: WorkerEnv, form: Record<string, string>): Promise<JsonObject> {
	const clientID = requiredEnv(env, 'SONOS_CLIENT_ID');
	const clientSecret = requiredEnv(env, 'SONOS_CLIENT_SECRET');
	const credentials = btoa(`${clientID}:${clientSecret}`);
	const response = await fetch(SONOS_TOKEN_URL, {
		method: 'POST',
		headers: {
			Authorization: `Basic ${credentials}`,
			'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
			Accept: 'application/json',
		},
		body: new URLSearchParams(form),
	});
	const text = await response.text();

	if (!response.ok) {
		let detail: unknown = text;
		try {
			detail = JSON.parse(text);
		} catch {
			// Sonos can return HTML for some OAuth errors. Preserve the status, not the page.
		}

		throw new HTTPError(response.status, 'sonos_error', { error: 'sonos_error', detail });
	}

	try {
		return JSON.parse(text) as JsonObject;
	} catch {
		throw new HTTPError(502, 'invalid_sonos_response');
	}
}

function requireBearerAccessToken(request: Request): string {
	const authorization = request.headers.get('Authorization') ?? '';
	const match = /^Bearer\s+(.+)$/i.exec(authorization);
	if (!match?.[1]) {
		throw new HTTPError(401, 'missing_authorization');
	}

	return match[1];
}

async function validateSonosAccessToken(accessToken: string): Promise<void> {
	const response = await fetch(`${SONOS_CONTROL_API_BASE_URL}/households`, {
		method: 'GET',
		headers: {
			Authorization: `Bearer ${accessToken}`,
			Accept: 'application/json',
			'User-Agent': 'Sonoic Cloud Queue Worker',
		},
	});

	if (response.ok) {
		return;
	}

	if (response.status === 401 || response.status === 403) {
		throw new HTTPError(401, 'invalid_authorization');
	}

	throw new HTTPError(502, 'sonos_authorization_check_failed');
}

function redirectToApp(env: WorkerEnv, query: Record<string, string>): Response {
	const appRedirectURI = requiredEnv(env, 'SONOIC_APP_REDIRECT_URI');
	const location = new URL(appRedirectURI);
	for (const [key, value] of Object.entries(query)) {
		location.searchParams.set(key, value);
	}

	return new Response(null, {
		status: 302,
		headers: {
			Location: location.toString(),
			'Cache-Control': 'no-store',
		},
	});
}

async function readJson(request: Request): Promise<JsonObject> {
	let body: unknown;
	try {
		body = await request.json();
	} catch {
		throw new HTTPError(400, 'request_body_must_be_json');
	}

	if (!body || typeof body !== 'object' || Array.isArray(body)) {
		throw new HTTPError(400, 'request_body_must_be_json_object');
	}

	return body as JsonObject;
}

function requiredString(body: JsonObject, key: string): string {
	const value = body[key];
	if (typeof value !== 'string' || value.length === 0) {
		throw new HTTPError(400, `missing_required_field:${key}`);
	}

	return value;
}

function requiredNumber(body: JsonObject, key: string): number {
	const value = body[key];
	if (typeof value !== 'number' || !Number.isFinite(value)) {
		throw new HTTPError(400, `missing_required_field:${key}`);
	}

	return value;
}

function requiredObject(body: JsonObject, key: string): JsonObject {
	const value = body[key];
	if (!isJsonObject(value)) {
		throw new HTTPError(400, `missing_required_field:${key}`);
	}

	return value;
}

function requiredObjectArray(body: JsonObject, key: string): JsonObject[] {
	const value = body[key];
	if (!Array.isArray(value) || !value.every(isJsonObject)) {
		throw new HTTPError(400, `missing_required_field:${key}`);
	}

	return value;
}

function optionalString(body: JsonObject, key: string): string | undefined {
	const value = body[key];
	return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function requiredEnv(env: WorkerEnv, key: keyof WorkerEnv & string): string {
	const value = env[key];
	if (typeof value !== 'string' || value.length === 0) {
		throw new HTTPError(500, `missing_required_env:${key}`);
	}

	return value;
}

async function callSonoicCloudQueues(env: WorkerEnv, path: string, request: Request): Promise<Response> {
	const namespace = env.SONOIC_CLOUD_QUEUES;
	if (!namespace) {
		throw new HTTPError(500, 'missing_required_env:SONOIC_CLOUD_QUEUES');
	}

	const id = namespace.idFromName('global');
	const stub = namespace.get(id);
	const headers = new Headers(request.headers);
	headers.set(EXTERNAL_ORIGIN_HEADER, new URL(request.url).origin);
	return await stub.fetch(new Request(new URL(path, 'https://sonoic-cloud-queues'), {
		method: request.method,
		headers,
		body: request.body,
	}));
}

function externalOrigin(request: Request): string {
	const value = request.headers.get(EXTERNAL_ORIGIN_HEADER);
	if (!value) {
		return new URL(request.url).origin;
	}

	try {
		return new URL(value).origin;
	} catch {
		return new URL(request.url).origin;
	}
}

function validateRedirectURI(env: WorkerEnv, redirectURI: string): void {
	const expected = requiredEnv(env, 'SONOS_REDIRECT_URI');
	if (redirectURI !== expected) {
		throw new HTTPError(400, 'redirect_uri_mismatch');
	}
}

async function makeBrokerCode(env: WorkerEnv, payload: BrokerCodePayload): Promise<string> {
	const payloadPart = base64URLEncode(textEncoder.encode(JSON.stringify(payload)));
	const signaturePart = await hmacSignature(env, payloadPart);
	return `${payloadPart}.${signaturePart}`;
}

async function readBrokerCode(env: WorkerEnv, brokerCode: string, expectedState: string): Promise<BrokerCodePayload> {
	const [payloadPart, signaturePart, extraPart] = brokerCode.split('.');
	if (!payloadPart || !signaturePart || extraPart !== undefined) {
		throw new HTTPError(400, 'invalid_broker_code');
	}

	const expectedSignature = await hmacSignature(env, payloadPart);
	if (!constantTimeEqual(signaturePart, expectedSignature)) {
		throw new HTTPError(400, 'invalid_broker_code');
	}

	let payload: unknown;
	try {
		payload = JSON.parse(textDecoder.decode(base64URLDecode(payloadPart)));
	} catch {
		throw new HTTPError(400, 'invalid_broker_code');
	}

	if (!isBrokerCodePayload(payload)) {
		throw new HTTPError(400, 'invalid_broker_code');
	}

	if (payload.state !== expectedState) {
		throw new HTTPError(400, 'state_mismatch');
	}

	if (payload.expiresAt < currentEpochSeconds()) {
		throw new HTTPError(400, 'expired_broker_code');
	}

	return payload;
}

async function reserveBrokerCodeRedemption(env: WorkerEnv, brokerCode: string, expiresAt: number): Promise<void> {
	const response = await callBrokerCodeRedemptions(env, brokerCode, '/reserve', { expires_at: expiresAt });
	if (response.status === 409) {
		throw new HTTPError(400, 'broker_code_redeemed');
	}

	if (!response.ok) {
		throw new HTTPError(500, 'broker_code_redemption_failed');
	}
}

async function completeBrokerCodeRedemption(env: WorkerEnv, brokerCode: string): Promise<void> {
	const response = await callBrokerCodeRedemptions(env, brokerCode, '/complete');
	if (!response.ok) {
		throw new HTTPError(500, 'broker_code_redemption_failed');
	}
}

async function releaseBrokerCodeRedemption(env: WorkerEnv, brokerCode: string): Promise<void> {
	const response = await callBrokerCodeRedemptions(env, brokerCode, '/release');
	if (!response.ok) {
		throw new HTTPError(500, 'broker_code_redemption_failed');
	}
}

async function callBrokerCodeRedemptions(
	env: WorkerEnv,
	brokerCode: string,
	path: '/reserve' | '/complete' | '/release',
	extraBody: JsonObject = {},
): Promise<Response> {
	const namespace = env.SONOS_BROKER_CODE_REDEMPTIONS;
	if (!namespace) {
		throw new HTTPError(500, 'missing_required_env:SONOS_BROKER_CODE_REDEMPTIONS');
	}

	const id = namespace.idFromName('global');
	const stub = namespace.get(id);
	return await stub.fetch(`https://broker-code-redemptions${path}`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			digest: await sha256Digest(brokerCode),
			...extraBody,
		}),
	});
}

function isBrokerCodePayload(payload: unknown): payload is BrokerCodePayload {
	if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
		return false;
	}

	const candidate = payload as Record<string, unknown>;
	return (
		typeof candidate.code === 'string' &&
		candidate.code.length > 0 &&
		typeof candidate.state === 'string' &&
		candidate.state.length > 0 &&
		typeof candidate.expiresAt === 'number' &&
		Number.isFinite(candidate.expiresAt)
	);
}

async function hmacSignature(env: WorkerEnv, value: string): Promise<string> {
	const secret = requiredEnv(env, 'SONOS_CLIENT_SECRET');
	const key = await crypto.subtle.importKey('raw', textEncoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
	const signature = await crypto.subtle.sign('HMAC', key, textEncoder.encode(value));
	return base64URLEncode(new Uint8Array(signature));
}

async function sha256Digest(value: string): Promise<string> {
	const digest = await crypto.subtle.digest('SHA-256', textEncoder.encode(value));
	return base64URLEncode(new Uint8Array(digest));
}

function base64URLEncode(bytes: Uint8Array): string {
	let binary = '';
	for (const byte of bytes) {
		binary += String.fromCharCode(byte);
	}

	return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function base64URLDecode(value: string): Uint8Array {
	const padded = value.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (value.length % 4)) % 4);
	const binary = atob(padded);
	const bytes = new Uint8Array(binary.length);
	for (let index = 0; index < binary.length; index += 1) {
		bytes[index] = binary.charCodeAt(index);
	}

	return bytes;
}

function constantTimeEqual(left: string, right: string): boolean {
	if (left.length !== right.length) {
		return false;
	}

	let mismatch = 0;
	for (let index = 0; index < left.length; index += 1) {
		mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
	}

	return mismatch === 0;
}

function currentEpochSeconds(): number {
	return Math.floor(Date.now() / 1_000);
}

function validateCloudQueueItem(item: JsonObject, index: number): string {
	const id = validatedCloudQueueItemID(item, index);
	const track = requiredCloudQueueTrack(item, index);
	validateCloudQueueTrack(track, index);
	return id;
}

function validatedCloudQueueItemID(item: JsonObject, index: number): string {
	const id = optionalString(item, 'id');
	if (!id) {
		throw new HTTPError(400, `cloud_queue_item_missing_id:${index}`);
	}

	if (id.length > 128) {
		throw new HTTPError(400, `cloud_queue_item_id_too_long:${index}`);
	}

	return id;
}

function requiredCloudQueueTrack(item: JsonObject, index: number): JsonObject {
	const track = item.track;
	if (!isJsonObject(track)) {
		throw new HTTPError(400, `cloud_queue_item_missing_track:${index}`);
	}

	return track;
}

function validateCloudQueueTrack(track: JsonObject, index: number): void {
	const hasRequiredMetadata =
		optionalString(track, 'name') !== undefined &&
		optionalString(track, 'contentType') !== undefined;
	if (!hasRequiredMetadata || !cloudQueueTrackHasPlaybackReference(track)) {
		throw new HTTPError(400, `cloud_queue_item_invalid_track:${index}`);
	}
}

function cloudQueueTrackHasPlaybackReference(track: JsonObject): boolean {
	if (optionalString(track, 'mediaUrl') !== undefined) {
		return true;
	}

	const trackID = track.id;
	return isJsonObject(trackID) && optionalString(trackID, 'objectId') !== undefined;
}

function clampedWindowSize(rawValue: string | null, defaultValue: number): number {
	const parsed = rawValue === null ? defaultValue : Number.parseInt(rawValue, 10);
	if (!Number.isFinite(parsed) || parsed < 0) {
		return defaultValue;
	}

	return Math.min(parsed, CLOUD_QUEUE_MAX_WINDOW_ITEMS - 1);
}

function isJsonObject(value: unknown): value is JsonObject {
	return !!value && typeof value === 'object' && !Array.isArray(value);
}

function jsonResponse(status: number, body: JsonObject): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: {
			'Content-Type': 'application/json',
			'Cache-Control': 'no-store',
		},
	});
}
