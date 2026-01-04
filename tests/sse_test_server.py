#!/usr/bin/env python3
"""Simple SSE test server for testing proxzy streaming."""

from http.server import HTTPServer, BaseHTTPRequestHandler
import time

# Delay between events (seconds) - keep short for fast tests
EVENT_DELAY = 0.01

class SSEHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/events':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'close')  # Close after stream ends
            self.end_headers()

            # Send 5 events
            for i in range(5):
                event = f"data: Event {i+1} at {time.time()}\n\n"
                self.wfile.write(event.encode())
                self.wfile.flush()
                print(f"Sent: {event.strip()}")
                time.sleep(EVENT_DELAY)

            # Final event
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"SSE test server. Use /events for SSE stream.")

    def log_message(self, format, *args):
        print(f"[Server] {args[0]}")

if __name__ == '__main__':
    port = 18765
    server = HTTPServer(('127.0.0.1', port), SSEHandler)
    print(f"SSE test server running on http://127.0.0.1:{port}")
    print(f"Test with: curl -N http://127.0.0.1:{port}/events")
    server.serve_forever()
