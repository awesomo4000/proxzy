#!/bin/bash
# Downloads the latest Mozilla CA certificate bundle from curl.se
# Run this periodically to update the embedded certificates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEST="$REPO_ROOT/src/cacert.pem"
URL="https://curl.se/ca/cacert.pem"

echo "Downloading CA certificates from $URL..."
curl -fsSL "$URL" -o "$DEST"

# Show some info about what we downloaded
CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$DEST" || echo "0")
FILE_SIZE=$(wc -c < "$DEST" | tr -d ' ')
DATE=$(date +%Y-%m-%d)

echo "Downloaded $CERT_COUNT certificates ($FILE_SIZE bytes)"
echo "Saved to: $DEST"
echo ""
echo "Don't forget to commit the updated cacert.pem!"
