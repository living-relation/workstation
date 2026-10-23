"""The toggle API runs on the dashboard's own PC and works from the phone (tailnet) with the token."""

import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import server  # noqa: E402


class ToggleApiTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self._switch, self._token = server.toggles.switch, server.read_token
        server.toggles.switch = lambda tid, on: self.calls.append((tid, on)) or {"ok": True, "started": True}
        server.read_token = lambda: "secret"
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}/api/toggle"

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        server.toggles.switch, server.read_token = self._switch, self._token

    def post(self, headers):
        body = json.dumps({"id": "remote", "action": "on"}).encode()
        req = urllib.request.Request(self.url, data=body, method="POST", headers={"Content-Type": "application/json", **headers})
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status
        except urllib.error.HTTPError as exc:
            return exc.code

    def test_phone_over_tailnet_with_token_runs_on_this_pc(self):
        phone = {"X-Forwarded-For": "100.64.0.9", "Host": "pc.example.ts.net"}
        self.assertEqual(self.post({**phone, "Authorization": "Bearer secret"}), 200)
        self.assertEqual(self.calls, [("remote", True)])

    def test_phone_without_token_is_refused(self):
        self.assertEqual(self.post({"X-Forwarded-For": "100.64.0.9", "Host": "pc.example.ts.net"}), 401)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
