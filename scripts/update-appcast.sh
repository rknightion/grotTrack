#!/usr/bin/env bash
#
# update-appcast.sh — Generate or update appcast.xml for Sparkle auto-updates.
#
# Usage: ./scripts/update-appcast.sh <version> <signature> <length>
#
# Arguments:
#   version   — Release version (e.g., "0.12.0")
#   signature — EdDSA signature from sign_update (base64 string)
#   length    — File size in bytes of GrotTrack.zip
#
# Expects appcast.xml in the current directory (creates it if missing).

set -euo pipefail

VERSION="${1:?Usage: update-appcast.sh <version> <signature> <length>}"
SIGNATURE="${2:?Missing EdDSA signature}"
LENGTH="${3:?Missing file length}"

DOWNLOAD_URL="https://github.com/rknightion/grotTrack/releases/download/v${VERSION}/GrotTrack.zip"
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S %z')"

NEW_ITEM="    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url=\"${DOWNLOAD_URL}\"
        sparkle:edSignature=\"${SIGNATURE}\"
        length=\"${LENGTH}\"
        type=\"application/octet-stream\"/>
    </item>"

if [ -f appcast.xml ]; then
  # Insert new item at the top of the channel (after <channel> + <title> lines).
  # Write the item to a temp file to avoid awk multiline -v limitations on macOS.
  ITEM_FILE="$(mktemp "${TMPDIR:-/tmp}/appcast-item.XXXXXX")"
  printf '%s\n' "$NEW_ITEM" > "$ITEM_FILE"
  awk -v itemfile="$ITEM_FILE" '
    /<\/title>/ && !inserted {
      print
      while ((getline line < itemfile) > 0) print line
      inserted=1
      next
    }
    { print }
  ' appcast.xml > appcast.xml.tmp
  rm -f "$ITEM_FILE"
  mv appcast.xml.tmp appcast.xml
else
  # Create new appcast.xml
  cat > appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GrotTrack Updates</title>
${NEW_ITEM}
  </channel>
</rss>
APPCAST
fi

echo "Appcast updated with version ${VERSION}"
