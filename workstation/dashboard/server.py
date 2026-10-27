"""Local dashboard server. Listens on 127.0.0.1 only.

Tailscale Serve, started separately, publishes that port on the tailnet.
This process never binds a public address and never turns on Funnel.
"""

from __future__ import annotations

import json
import mimetypes
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse

import collect
import send

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "toggles"))
import toggles  # noqa: E402

HERE = Path(__file__).resolve().parent
STATIC = HERE / "static"
PORT = collect.PORT
_LOCK = threading.Lock()
_CACHE: dict[str, tuple[float, dict]] = {}


def token_path() -> Path:
    return collect.state_dir() / "token.txt"


def read_token() -> str:
    path = token_path()
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8").strip()


def snapshot(lite: bool) -> dict:
    key = "lite" if lite else "full"
    now = time.time()
    with _LOCK:
        hit = _CACHE.get(key)
        if hit and now - hit[0] < 12:
            return hit[1]
    data = collect.build_snapshot(lite=lite)
    with _LOCK:
        _CACHE[key] = (time.time(), data)
    return data


class Handler(BaseHTTPRequestHandler):
    server_version = "WorkstationDashboard"

    def log_message(self, fmt: str, *args) -> None:
        path = urlparse(self.path).path
        print(f"{self.address_string()} {self.command} {path}")

    def _host(self) -> str:
        raw = (self.headers.get("Host") or "").split(",")[0].strip()
        raw = raw.split(":")[0].strip("[]").lower()
        return raw

    def _local_browser(self) -> bool:
        if self.headers.get("X-Forwarded-For") or self.headers.get("X-Forwarded-Host"):
            return False
        if any(key.lower().startswith("tailscale-") for key in self.headers):
            return False
        client = self.client_address[0]
        return client in {"127.0.0.1", "::1"} and self._host() in {"127.0.0.1", "localhost", "::1"}

    def _authorized(self) -> bool:
        if self._local_browser():
            return True
        expected = read_token()
        if not expected:
            return False
        query = parse_qs(urlparse(self.path).query)
        supplied = (query.get("token") or [""])[0]
        header = self.headers.get("Authorization") or ""
        cookie = self.headers.get("Cookie") or ""
        cookie_token = ""
        for part in cookie.split(";"):
            name, _, value = part.strip().partition("=")
            if name == "dash":
                cookie_token = value
        if supplied == expected or header == f"Bearer {expected}" or cookie_token == expected:
            return True
        return False

    def _https_request(self) -> bool:
        # Tailscale Serve terminates TLS and sets X-Forwarded-Proto.
        proto = (self.headers.get("X-Forwarded-Proto") or "").split(",")[0].strip().lower()
        return proto == "https"

    def _cookie_header(self, token: str) -> str:
        # Prefer HTTPS (Serve). Secure is set only then so the cookie is not
        # offered on plain http://100.x. Phone bookmarks should use the HTTPS link.
        parts = [f"dash={token}", "Path=/", "HttpOnly", "SameSite=Lax"]
        if self._https_request():
            parts.append("Secure")
        return "; ".join(parts)

    def _redirect_strip_token(self, token: str) -> bool:
        """If ?token= matches, set session cookie and redirect without the token."""
        if self._local_browser():
            return False
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query, keep_blank_values=True)
        supplied = (query.get("token") or [""])[0]
        if not supplied or supplied != token:
            return False
        query.pop("token", None)
        new_query = urlencode(
            [(key, value) for key, values in query.items() for value in values],
            doseq=False,
        )
        location = parsed.path or "/"
        if new_query:
            location = f"{location}?{new_query}"
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Set-Cookie", self._cookie_header(token))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", "0")
        self.end_headers()
        return True

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _bytes(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict | None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 32_000:
            return None
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None
        return data if isinstance(data, dict) else None

    def _session(self, app: str, session_id: str) -> dict | None:
        data = snapshot(lite=True)
        groups = data.get("sessions") or {}
        for rows in groups.values():
            if not isinstance(rows, list):
                continue
            for row in rows:
                if row.get("app") == app and str(row.get("id")) == session_id:
                    return row
        return None

    def do_GET(self) -> None:  # noqa: N802
        expected = read_token()
        if expected and self._redirect_strip_token(expected):
            return
        if not self._authorized():
            self._json(401, {"error": "token required"})
            return
        parsed = urlparse(self.path)
        path = parsed.path
        if path in {"/", "/index.html"}:
            self._bytes(200, (STATIC / "index.html").read_bytes(), "text/html; charset=utf-8")
            return
        if path.startswith("/static/"):
            name = path[len("/static/") :]
            if not name or "/" in name or "\\" in name or name.startswith("."):
                self._json(404, {"error": "not found"})
                return
            file = STATIC / name
            if not file.is_file():
                self._json(404, {"error": "not found"})
                return
            mime = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
            self._bytes(200, file.read_bytes(), mime)
            return
        if path == "/api/health":
            self._json(200, {"ok": True, "port": PORT})
            return
        if path == "/api/toggles":
            self._json(200, {"toggles": toggles.snapshot()})
            return
        if path == "/api/snapshot":
            lite = "1" in (parse_qs(parsed.query).get("lite") or [])
            self._json(200, snapshot(lite=lite))
            return
        if path == "/media":
            query = parse_qs(parsed.query)
            project = (query.get("project") or [""])[0]
            rel = (query.get("rel") or [""])[0]
            file = collect.project_file(project, rel)
            if file is None or file.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp", ".gif"}:
                self._json(404, {"error": "not found"})
                return
            mime = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
            self._bytes(200, file.read_bytes(), mime)
            return
        if path == "/preview":
            query = parse_qs(parsed.query)
            png = collect.render_pdf_png((query.get("project") or [""])[0], (query.get("rel") or [""])[0])
            if not png:
                self._json(404, {"error": "not found"})
                return
            self._bytes(200, png, "image/png")
            return
        if path == "/doc":
            query = parse_qs(parsed.query)
            file = collect.project_file((query.get("project") or [""])[0], (query.get("rel") or [""])[0])
            if file is None or file.suffix.lower() not in {".md", ".markdown", ".rst", ".txt"}:
                self._json(404, {"error": "not found"})
                return
            try:
                text = file.read_text(encoding="utf-8", errors="replace")[:80_000]
            except OSError:
                self._json(404, {"error": "not found"})
                return
            self._json(200, {"title": file.name, "text": text})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._authorized():
            self._json(401, {"error": "token required"})
            return
        path = urlparse(self.path).path
        body = self._read_json()
        if body is None:
            self._json(400, {"error": "expected a small JSON body"})
            return
        if path == "/api/open-file":
            if not self._local_browser():
                self._json(403, {"error": "files open only on this PC"})
                return
            file = collect.project_file(str(body.get("project") or ""), str(body.get("rel") or ""))
            if file is None:
                self._json(404, {"ok": False, "error": "file not found"})
                return
            try:
                os.startfile(file)  # type: ignore[attr-defined]
            except OSError as exc:
                self._json(500, {"ok": False, "error": str(exc)})
                return
            self._json(200, {"ok": True, "opened": file.name})
            return
        if path == "/api/toggle":
            tid = str(body.get("id") or "")
            action = str(body.get("action") or "")
            if action not in {"on", "off"}:
                self._json(400, {"ok": False, "error": "action must be on or off"})
                return
            self._json(200, toggles.switch(tid, action == "on"))
            return
        if path == "/api/toggle-health":
            self._json(200, toggles.health(str(body.get("id") or "")))
            return
        if path == "/api/process-check":
            self._json(200, toggles.process_check())
            return
        if path == "/api/shortcut":
            if not self._local_browser():
                self._json(403, {"error": "shortcuts launch only from this PC"})
                return
            link = collect.shortcut_path(str(body.get("name") or ""))
            if link is None:
                self._json(404, {"error": "shortcut not found"})
                return
            try:
                os.startfile(link)  # type: ignore[attr-defined]
            except OSError as exc:
                self._json(500, {"ok": False, "error": str(exc)})
                return
            self._json(200, {"ok": True, "launched": link.name})
            return
        if path == "/api/send":
            app = str(body.get("app") or "")
            session_id = str(body.get("id") or "")
            row = self._session(app, session_id)
            if row is None:
                self._json(404, {"ok": False, "sent": False, "error": "session is not on the board"})
                return
            if not row.get("canSend"):
                self._json(409, {"ok": False, "sent": False, "error": row.get("sendNote") or "cannot send"})
                return
            self._json(200, send.deliver(app, row, str(body.get("text") or "")))
            return
        if path == "/api/open":
            app = str(body.get("app") or "")
            session_id = str(body.get("id") or "")
            row = self._session(app, session_id)
            if row is None:
                self._json(404, {"ok": False, "error": "session is not on the board"})
                return
            self._json(200, send.open_session(app, row))
            return
        self._json(404, {"error": "not found"})


def _serve(host: str) -> None:
    try:
        server = ThreadingHTTPServer((host, PORT), Handler)
    except OSError as exc:
        print(f"not listening on {host}: {exc}")
        return
    print(f"dashboard http://{host}:{PORT}/")
    server.serve_forever()


def main() -> None:
    extra = [
        host.strip()
        for host in os.environ.get("DASHBOARD_BIND", "").split(",")
        if host.strip() and host.strip() not in {"0.0.0.0", "::", "127.0.0.1"}
    ]
    for host in extra:
        threading.Thread(target=_serve, args=(host,), daemon=True).start()
    _serve("127.0.0.1")


if __name__ == "__main__":
    main()
