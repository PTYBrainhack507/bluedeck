#!/usr/bin/env python3
"""Servidor estático dual-stack (IPv4 + IPv6) para previsualizar la PWA de BlueDeck."""
import http.server, socketserver, socket, sys, os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
os.chdir(os.path.dirname(os.path.abspath(__file__)))

class DualStackServer(socketserver.TCPServer):
    allow_reuse_address = True
    address_family = socket.AF_INET6
    def server_bind(self):
        # acepta conexiones IPv4 (127.0.0.1) e IPv6 (::1) en el mismo socket
        try:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        except (AttributeError, OSError):
            pass
        super().server_bind()

Handler = http.server.SimpleHTTPRequestHandler
with DualStackServer(("", PORT), Handler) as httpd:
    print(f"BlueDeck PWA en http://localhost:{PORT}/ (dual-stack)", flush=True)
    httpd.serve_forever()
