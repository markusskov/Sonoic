#!/usr/bin/env python3
"""Local development Sonos OAuth token broker.

This server is intentionally tiny and dependency-free. It keeps the Sonos
client secret on the Mac during development while the iOS app talks only to
public HTTPS tunnel URLs.
"""

from __future__ import annotations

import base64
import datetime
import json
import os
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


SONOS_TOKEN_URL = "https://api.sonos.com/login/v3/oauth/access"
BROKER_CODE_TTL_SECONDS = 300
OAUTH_CALLBACK_PATHS = {"/oauth/sonos/callback", "/oauth"}


@dataclass
class BrokerConfig:
    client_id: str
    client_secret: str
    redirect_uri: str
    app_redirect_uri: str
    host: str
    port: int

    @staticmethod
    def load() -> "BrokerConfig":
        return BrokerConfig(
            client_id=required_env("SONOS_CLIENT_ID"),
            client_secret=required_env("SONOS_CLIENT_SECRET"),
            redirect_uri=required_env("SONOS_REDIRECT_URI"),
            app_redirect_uri=os.environ.get("SONOIC_APP_REDIRECT_URI", "sonoic://sonos-auth"),
            host=os.environ.get("SONOIC_BROKER_HOST", "127.0.0.1"),
            port=int(os.environ.get("SONOIC_BROKER_PORT", "3000")),
        )


@dataclass
class PendingAuthorization:
    sonos_code: str
    state: str
    created_at: float

    @property
    def is_expired(self) -> bool:
        return time.time() - self.created_at > BROKER_CODE_TTL_SECONDS


class BrokerStore:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._pending: dict[str, PendingAuthorization] = {}

    def issue(self, sonos_code: str, state: str) -> str:
        self._prune_expired()
        broker_code = secrets.token_urlsafe(32)
        with self._lock:
            self._pending[broker_code] = PendingAuthorization(
                sonos_code=sonos_code,
                state=state,
                created_at=time.time(),
            )
        return broker_code

    def redeem(self, broker_code: str, expected_state: str) -> PendingAuthorization:
        self._prune_expired()
        with self._lock:
            pending = self._pending.pop(broker_code, None)

        if pending is None:
            raise BrokerHTTPError(404, "Unknown or expired broker code.")
        if pending.is_expired:
            raise BrokerHTTPError(410, "Expired broker code.")
        if pending.state != expected_state:
            raise BrokerHTTPError(400, "OAuth state mismatch.")
        return pending

    def _prune_expired(self) -> None:
        now = time.time()
        with self._lock:
            expired = [
                code
                for code, pending in self._pending.items()
                if now - pending.created_at > BROKER_CODE_TTL_SECONDS
            ]
            for code in expired:
                self._pending.pop(code, None)


class BrokerHTTPError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


class SonosTokenBrokerHandler(BaseHTTPRequestHandler):
    config: BrokerConfig
    store: BrokerStore

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/healthz":
            self.write_json(200, {"ok": True})
            return
        if parsed.path in OAUTH_CALLBACK_PATHS:
            self.handle_oauth_callback(parsed)
            return

        self.write_json(404, {"error": "not_found"})

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        try:
            if parsed.path == "/api/sonos/token":
                self.handle_token_exchange()
                return
            if parsed.path == "/api/sonos/token/refresh":
                self.handle_token_refresh()
                return
            if parsed.path == "/api/sonos/events":
                self.log_broker_event("event callback received")
                self.write_json(202, {"success": True})
                return

            self.write_json(404, {"error": "not_found"})
        except BrokerHTTPError as error:
            self.write_json(error.status, {"error": error.message})
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            self.write_json(error.code, {"error": "sonos_error", "detail": body})
        except Exception as error:  # noqa: BLE001 - dev server should return diagnostics.
            self.write_json(500, {"error": "broker_error", "detail": str(error)})

    def handle_oauth_callback(self, parsed: urllib.parse.ParseResult) -> None:
        self.log_broker_event("oauth callback received")
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        state = single_query_value(query, "state")

        sonos_error = single_query_value(query, "error")
        if sonos_error:
            self.log_broker_event(f"oauth callback error: {sonos_error}")
            self.redirect_to_app({"error": sonos_error, "state": state or ""})
            return

        sonos_code = single_query_value(query, "code")
        if not sonos_code or not state:
            self.log_broker_event("oauth callback missing code or state")
            self.redirect_to_app({"error": "missing_code_or_state", "state": state or ""})
            return

        broker_code = self.store.issue(sonos_code=sonos_code, state=state)
        self.log_broker_event("oauth callback issued broker code")
        self.redirect_to_app({"broker_code": broker_code, "state": state})

    def handle_token_exchange(self) -> None:
        self.log_broker_event("token exchange requested")
        body = self.read_json()
        broker_code = required_body_string(body, "code")
        state = required_body_string(body, "state")
        pending = self.store.redeem(broker_code, expected_state=state)
        response = self.request_sonos_token(
            {
                "grant_type": "authorization_code",
                "code": pending.sonos_code,
                "redirect_uri": self.config.redirect_uri,
            }
        )
        self.write_json(200, response)

    def handle_token_refresh(self) -> None:
        self.log_broker_event("token refresh requested")
        body = self.read_json()
        refresh_token = required_body_string(body, "refresh_token")
        response = self.request_sonos_token(
            {
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
            }
        )
        self.write_json(200, response)

    def request_sonos_token(self, form: dict[str, str]) -> dict[str, Any]:
        credentials = f"{self.config.client_id}:{self.config.client_secret}".encode("utf-8")
        request = urllib.request.Request(
            SONOS_TOKEN_URL,
            data=urllib.parse.urlencode(form).encode("utf-8"),
            headers={
                "Authorization": "Basic " + base64.b64encode(credentials).decode("ascii"),
                "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
                "Accept": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.loads(response.read().decode("utf-8"))

    def redirect_to_app(self, query: dict[str, str]) -> None:
        separator = "&" if "?" in self.config.app_redirect_uri else "?"
        location = self.config.app_redirect_uri + separator + urllib.parse.urlencode(query)
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def read_json(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        try:
            body = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError as error:
            raise BrokerHTTPError(400, "Request body must be JSON.") from error
        if not isinstance(body, dict):
            raise BrokerHTTPError(400, "Request body must be a JSON object.")
        return body

    def write_json(self, status: int, body: dict[str, Any]) -> None:
        encoded = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"[sonos-token-broker] {self.address_string()} - {format % args}")

    def log_broker_event(self, message: str) -> None:
        print(f"[sonos-token-broker] {timestamp()} {message}")


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def timestamp() -> str:
    return datetime.datetime.now(tz=datetime.UTC).isoformat(timespec="seconds")


def redacted(value: str) -> str:
    if len(value) <= 8:
        return "<set>"
    return f"{value[:4]}…{value[-4:]}"


def single_query_value(query: dict[str, list[str]], name: str) -> str | None:
    values = query.get(name)
    if not values:
        return None
    return values[0]


def required_body_string(body: dict[str, Any], name: str) -> str:
    value = body.get(name)
    if not isinstance(value, str) or not value:
        raise BrokerHTTPError(400, f"Missing required field: {name}")
    return value


def main() -> None:
    config = BrokerConfig.load()
    SonosTokenBrokerHandler.config = config
    SonosTokenBrokerHandler.store = BrokerStore()
    server = ThreadingHTTPServer((config.host, config.port), SonosTokenBrokerHandler)
    parsed_redirect = urllib.parse.urlparse(config.redirect_uri)
    event_callback_url = urllib.parse.urlunparse(
        parsed_redirect._replace(path="/api/sonos/events", query="", fragment="")
    )
    print(f"[sonos-token-broker] listening on http://{config.host}:{config.port}")
    print(f"[sonos-token-broker] client id: {redacted(config.client_id)}")
    print(f"[sonos-token-broker] redirect uri: {config.redirect_uri}")
    print(f"[sonos-token-broker] event callback url: {event_callback_url}")
    print(f"[sonos-token-broker] app redirect uri: {config.app_redirect_uri}")
    print(f"[sonos-token-broker] forward with: cloudflared tunnel --url http://{config.host}:{config.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
