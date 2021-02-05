#!/bin/bash
set -e

RELEASE="$(curl -fsSL https://api.spritsail.io/plex/release | jq -c)"
VERSION="$(jq -r .version <<< "$RELEASE")"
CHECKSUM="$(jq -r '.["csum-deb"]' <<< "$RELEASE")"

sed -Ei \
    -e "s/^(ARG PLEX_VER=).*$/\1$VERSION/" \
    -e "s/^(ARG PLEX_SHA=).*$/\1$CHECKSUM/" \
    Dockerfile

if ! git diff --quiet --exit-code Dockerfile; then
    git reset --soft
    git add -- Dockerfile
    git commit \
        --author="Spritsail Bot <bot@spritsail.io>" \
        --no-gpg-sign \
        -m "Update to Plex ${VERSION%-*}"
    git push origin HEAD
else
    >&2 echo No update available
fi
