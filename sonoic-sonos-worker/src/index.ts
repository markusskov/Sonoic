const SONOS_TOKEN_URL = 'https://api.sonos.com/login/v3/oauth/access';
const OAUTH_CALLBACK_PATHS = new Set(['/oauth/sonos/callback', '/oauth']);
const BROKER_CODE_TTL_SECONDS = 5 * 60;
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

type WorkerEnv = Env & {
	SONOS_CLIENT_SECRET?: string;
	SONOS_BROKER_CODE_REDEMPTIONS?: DurableObjectNamespace;
};

type JsonObject = Record<string, unknown>;

type BrokerCodePayload = {
	code: string;
	state: string;
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
		const expiresAt = requiredNumber(body, 'expires_at');
		const storageKey = `broker-code:${digest}`;
		const existing = await this.state.storage.get(storageKey);
		if (existing !== undefined) {
			return jsonResponse(409, { error: 'broker_code_redeemed' });
		}

		await this.state.storage.put(storageKey, expiresAt);
		return jsonResponse(201, { success: true });
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

			return jsonResponse(404, { error: 'not_found' });
		} catch (error) {
			if (error instanceof HTTPError) {
				return jsonResponse(error.status, error.body ?? { error: error.message });
			}

			return jsonResponse(500, { error: 'broker_error' });
		}
	},
} satisfies ExportedHandler<Env>;

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
	await markBrokerCodeRedeemed(env, brokerCode, payload.expiresAt);

	const tokenResponse = await requestSonosToken(env, {
		grant_type: 'authorization_code',
		code: payload.code,
		redirect_uri: redirectURI,
	});
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

function requiredEnv(env: WorkerEnv, key: keyof WorkerEnv & string): string {
	const value = env[key];
	if (typeof value !== 'string' || value.length === 0) {
		throw new HTTPError(500, `missing_required_env:${key}`);
	}

	return value;
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

async function markBrokerCodeRedeemed(env: WorkerEnv, brokerCode: string, expiresAt: number): Promise<void> {
	const namespace = env.SONOS_BROKER_CODE_REDEMPTIONS;
	if (!namespace) {
		throw new HTTPError(500, 'missing_required_env:SONOS_BROKER_CODE_REDEMPTIONS');
	}

	const id = namespace.idFromName('global');
	const stub = namespace.get(id);
	const response = await stub.fetch('https://broker-code-redemptions/redeem', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			digest: await sha256Digest(brokerCode),
			expires_at: expiresAt,
		}),
	});

	if (response.status === 409) {
		throw new HTTPError(400, 'broker_code_redeemed');
	}

	if (!response.ok) {
		throw new HTTPError(500, 'broker_code_redemption_failed');
	}
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

function jsonResponse(status: number, body: JsonObject): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: {
			'Content-Type': 'application/json',
			'Cache-Control': 'no-store',
		},
	});
}
