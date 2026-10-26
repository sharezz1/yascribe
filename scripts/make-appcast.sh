#!/bin/bash
# Użycie: scripts/make-appcast.sh <zip> <wersja> <build> <podpis> <długość>   → appcast.xml na stdout.
# Jeden <item>; adres zasobu wynika z nazwy zipa i wersji. Podpis EdDSA i długość podaje release.sh (sign_update).
set -euo pipefail
[ "$#" -eq 5 ] || { echo "make-appcast: użycie: <zip> <wersja> <build> <podpis> <długość>" >&2; exit 2; }
ZIP="$(basename "$1")"; VERSION="$2"; BUILD="$3"; SIG="$4"; LENGTH="$5"
cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Yascribe</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/sharezz1/yascribe/releases/download/v$VERSION/$ZIP" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIG"/>
    </item>
  </channel>
</rss>
EOF
