#!/usr/bin/env python3
"""SSE test server that deliberately fragments events across chunks.

This tests that the SSE accumulator properly combines partial chunks
until the \n\n boundary is reached.
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import time

# Delays (seconds) - keep short for fast tests
FRAGMENT_DELAY = 0.01  # Between fragments of same event
EVENT_DELAY = 0.02     # Between complete events

class FragmentedSSEHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/fragmented':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'close')  # Close after stream ends
            self.end_headers()

            # Send events fragmented across multiple writes
            # Each event is 51 bytes: "data: Event N - padding to make exactly 50 bytes!\n\n"
            events = [
                "data: Event 1 - padding to make exactly 50 bytes!\n\n",  # 51 bytes
                "data: Event 2 - padding to make exactly 50 bytes!\n\n",
                "data: Event 3 - padding to make exactly 50 bytes!\n\n",
            ]

            for event in events:
                expected_len = len(event)
                print(f"Sending event ({expected_len} bytes total) in fragments...")

                # Fragment 1: first 10 bytes
                frag1 = event[0:10]
                self.wfile.write(frag1.encode())
                self.wfile.flush()
                print(f"  Fragment 1: {len(frag1)} bytes: {repr(frag1)}")
                time.sleep(FRAGMENT_DELAY)

                # Fragment 2: next 20 bytes
                frag2 = event[10:30]
                self.wfile.write(frag2.encode())
                self.wfile.flush()
                print(f"  Fragment 2: {len(frag2)} bytes: {repr(frag2)}")
                time.sleep(FRAGMENT_DELAY)

                # Fragment 3: rest including \n\n
                frag3 = event[30:]
                self.wfile.write(frag3.encode())
                self.wfile.flush()
                print(f"  Fragment 3: {len(frag3)} bytes: {repr(frag3)}")
                time.sleep(EVENT_DELAY)

            # Final done event - also fragmented
            done = "data: [DONE]\n\n"
            self.wfile.write(done[:7].encode())  # "data: ["
            self.wfile.flush()
            time.sleep(FRAGMENT_DELAY)
            self.wfile.write(done[7:].encode())  # "DONE]\n\n"
            self.wfile.flush()
            print(f"Sent fragmented [DONE]")

        elif self.path == '/expected':
            # Return expected event lengths for verification
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            # Each complete event should be 51 bytes (including \n\n)
            self.wfile.write(b"51,51,51,14")  # 3 events + [DONE]
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"Fragmented SSE server. Use /fragmented for test, /expected for lengths.")

    def log_message(self, format, *args):
        print(f"[Server] {args[0]}")

if __name__ == '__main__':
    port = 18767
    server = HTTPServer(('127.0.0.1', port), FragmentedSSEHandler)
    print(f"Fragmented SSE test server running on http://127.0.0.1:{port}")
    print(f"Test with: curl -N http://127.0.0.1:{port}/fragmented")
    print(f"Expected lengths: curl http://127.0.0.1:{port}/expected")
    server.serve_forever()
