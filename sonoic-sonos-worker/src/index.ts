const SONOS_TOKEN_URL = 'https://api.sonos.com/login/v3/oauth/access';
const OAUTH_CALLBACK_PATHS = new Set(['/oauth/sonos/callback', '/oauth']);

type WorkerEnv = Env & {
	SONOS_CLIENT_SECRET?: string;
};

type JsonObject = Record<string, unknown>;

class HTTPError extends Error {
	constructor(
		readonly status: number,
		message: string,
		readonly body?: JsonObject,
	) {
		super(message);
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
				return handleOAuthCallback(url, env as WorkerEnv);
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

function handleOAuthCallback(url: URL, env: WorkerEnv): Response {
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

	return redirectToApp(env, { code, state });
}

async function handleTokenExchange(request: Request, env: WorkerEnv): Promise<Response> {
	const body = await readJson(request);
	const code = requiredString(body, 'code');
	const redirectURI = requiredString(body, 'redirect_uri');
	validateRedirectURI(env, redirectURI);

	const tokenResponse = await requestSonosToken(env, {
		grant_type: 'authorization_code',
		code,
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

function jsonResponse(status: number, body: JsonObject): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: {
			'Content-Type': 'application/json',
			'Cache-Control': 'no-store',
		},
	});
}
