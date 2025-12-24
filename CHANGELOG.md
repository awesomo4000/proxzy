# Changelog

## [0.0.1] - 12/14/2025

### Added
- Initial implementation of HTTP proxy
- httpz server for receiving HTTP requests
- libcurl + mbedTLS client for forwarding to upstream HTTPS servers
- Request/response logging with header redaction
- Configurable upstream URL, port, and logging options
- Header forwarding
