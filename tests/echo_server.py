#!/usr/bin/env python3
"""Local echo server that mimics httpbin.org endpoints for testing."""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json

PORT = 18080

class EchoHandler(BaseHTTPRequestHandler):
    def _send_json(self, data):
        body = json.dumps(data, indent=2).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        """Echo back request info (like httpbin.org/get)"""
        headers = {k: v for k, v in self.headers.items()}
        response = {
            "args": {},
            "headers": headers,
            "origin": "127.0.0.1",
            "url": f"http://127.0.0.1:{PORT}{self.path}"
        }
        self._send_json(response)

    def do_POST(self):
        """Echo back request info and body (like httpbin.org/post)"""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode() if content_length else ""
        headers = {k: v for k, v in self.headers.items()}

        response = {
            "args": {},
            "data": body,
            "headers": headers,
            "json": None,
            "origin": "127.0.0.1",
            "url": f"http://127.0.0.1:{PORT}{self.path}"
        }

        # Try to parse JSON body
        if body:
            try:
                response["json"] = json.loads(body)
            except json.JSONDecodeError:
                pass

        self._send_json(response)

    def log_message(self, format, *args):
        print(f"[Echo] {args[0]}")

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', PORT), EchoHandler)
    print(f"Echo server running on http://127.0.0.1:{PORT}")
    print(f"Mimics httpbin.org /get and /post endpoints")
    server.serve_forever()
