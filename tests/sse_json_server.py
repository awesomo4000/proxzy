#!/usr/bin/env python3
"""SSE test server that sends JSON events - for testing SSE transforms."""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import time

# Delay between events (seconds) - keep short for fast tests
EVENT_DELAY = 0.01

class SSEHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/stream':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'close')  # Close after stream ends
            self.end_headers()

            # Simulate LLM-style streaming responses
            messages = [
                {"model": "test-model", "content": "Hello", "tokens": 1},
                {"model": "test-model", "content": " world", "tokens": 1},
                {"model": "test-model", "content": "!", "tokens": 1},
                {"model": "test-model", "content": " How", "tokens": 1},
                {"model": "test-model", "content": " are", "tokens": 1},
                {"model": "test-model", "content": " you?", "tokens": 1},
            ]

            for i, msg in enumerate(messages):
                event = f"data: {json.dumps(msg)}\n\n"
                self.wfile.write(event.encode())
                self.wfile.flush()
                print(f"Sent: {event.strip()}")
                time.sleep(EVENT_DELAY)

            # Final event
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            print("Sent: data: [DONE]")
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"JSON SSE test server. Use /stream for SSE stream.")

    def log_message(self, format, *args):
        print(f"[Server] {args[0]}")

if __name__ == '__main__':
    port = 18766
    server = HTTPServer(('127.0.0.1', port), SSEHandler)
    print(f"JSON SSE test server running on http://127.0.0.1:{port}")
    print(f"Test with: curl -N http://127.0.0.1:{port}/stream")
    server.serve_forever()
