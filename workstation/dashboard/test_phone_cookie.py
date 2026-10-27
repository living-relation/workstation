"""Phone auth: ?token= sets the dash cookie (Secure on HTTPS) and redirects; cookie authorizes later calls."""

import json
import sys
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import server  # noqa: E402


PHONE = {"X-Forwarded-For": "100.64.0.9", "Host": "pc.example.ts.net"}
PHONE_HTTPS = {**PHONE, "X-Forwarded-Proto": "https"}


class PhoneCookieTests(unittest.TestCase):
    def setUp(self):
        self._token = server.read_token
        server.read_token = lambda: "secret"
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        server.read_token = self._token

    def _open(self, path, headers=None, jar=None):
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar or CookieJar()))
        # Do not auto-follow redirects so we can assert Set-Cookie + Location.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: N802
                return None

        opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar or CookieJar()),
            NoRedirect,
        )
        req = urllib.request.Request(self.base + path, headers=headers or {})
        try:
            return opener.open(req, timeout=5)
        except urllib.error.HTTPError as exc:
            return exc

    def test_token_query_sets_secure_cookie_and_redirects(self):
        resp = self._open("/?token=secret", headers=PHONE_HTTPS)
        self.assertEqual(resp.status, 302)
        self.assertEqual(resp.headers.get("Location"), "/")
        cookie = resp.headers.get("Set-Cookie") or ""
        self.assertIn("dash=secret", cookie)
        self.assertIn("Path=/", cookie)
        self.assertIn("HttpOnly", cookie)
        self.assertIn("SameSite=Lax", cookie)
        self.assertIn("Secure", cookie)

    def test_token_query_over_plain_http_omits_secure(self):
        # Direct http://100.x has no X-Forwarded-Proto; cookie still works on the tailnet.
        resp = self._open("/?token=secret", headers=PHONE)
        self.assertEqual(resp.status, 302)
        cookie = resp.headers.get("Set-Cookie") or ""
        self.assertIn("dash=secret", cookie)
        self.assertNotIn("Secure", cookie)

    def test_cookie_authorizes_static_and_api(self):
        jar = CookieJar()
        # First hit: set cookie via redirect (manual: put cookie ourselves after seeing Set-Cookie).
        first = self._open("/?token=secret", headers=PHONE_HTTPS, jar=jar)
        self.assertEqual(first.status, 302)
        # Simulate browser storing the cookie and requesting assets without ?token=.
        # urllib CookieJar may skip Secure cookies on http://127.0.0.1 — set Cookie header directly.
        headers = {**PHONE_HTTPS, "Cookie": "dash=secret"}
        css = self._open("/static/app.css", headers=headers)
        self.assertEqual(css.status, 200)
        health = self._open("/api/health", headers=headers)
        self.assertEqual(health.status, 200)
        body = json.loads(health.read().decode())
        self.assertTrue(body.get("ok"))

    def test_phone_without_cookie_or_token_is_refused(self):
        resp = self._open("/static/app.js", headers=PHONE_HTTPS)
        self.assertEqual(resp.status, 401)

    def test_wrong_token_query_is_refused(self):
        resp = self._open("/?token=nope", headers=PHONE_HTTPS)
        self.assertEqual(resp.status, 401)


if __name__ == "__main__":
    unittest.main()