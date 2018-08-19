#!/bin/sh
set -e

PREF_FILE="${1:-/config/Preferences.xml}"

getPref() {
    xmlstarlet sel -T -t -m "/Preferences" -v "@$1" -n "${PREF_FILE}"
}
setPref() {
    count="$(xmlstarlet sel -t -v "count(/Preferences/@$1)" "${PREF_FILE}")"
    if [ $(($count + 0)) -gt 0 ]; then
        xmlstarlet ed --inplace --update "/Preferences/@$1" -v "$2" "${PREF_FILE}" 2>/dev/null
    else
        xmlstarlet ed --inplace --insert "/Preferences"  --type attr -n "$1" -v "$2" "${PREF_FILE}" 2>/dev/null
    fi
}

# Create a default config file allowing external access
echo -e $'<?xml version="1.0" encoding="utf-8"?>\n<Preferences />' > "/config/Preferences.xml"

# Enforced defaults. These can be changed manually afterwards.
setPref "AcceptedEULA" "1"
setPref "TranscoderTempDirectory" "/transcode"

# The following below is ripped directly from the official (inferior) Plex container:
# https://github.com/plexinc/pms-docker/blob/155f00c71b50f94c73ffea0aae16cc61ef957df7/root/etc/cont-init.d/40-plex-first-run

# Setup Server's client identifier
serial="$(getPref "MachineIdentifier")"
if [ -z "${serial}" ]; then
    serial="$(cat /proc/sys/kernel/random/uuid)"
    setPref "MachineIdentifier" "${serial}"
fi
clientId="$(getPref "ProcessedMachineIdentifier")"
if [ -z "${clientId}" ]; then
    clientId="$(echo -n "${serial}- Plex Media Server" | sha1sum | cut -b 1-40)"
    setPref "ProcessedMachineIdentifier" "${clientId}"
fi

# Get server token and only turn claim token into server token if we have former but not latter.
token="$(getPref "PlexOnlineToken")"
if [ ! -z "${PLEX_CLAIM}" ] && [ -z "${token}" ]; then
    echo "Attempting to obtain server token from claim token"
    loginInfo="$(curl -X POST \
        -H 'X-Plex-Client-Identifier: '${clientId} \
        -H 'X-Plex-Product: Plex Media Server'\
        -H 'X-Plex-Version: 1.1' \
        -H 'X-Plex-Provides: server' \
        -H 'X-Plex-Platform: Linux' \
        -H 'X-Plex-Platform-Version: 1.0' \
        -H 'X-Plex-Device-Name: PlexMediaServer' \
        -H 'X-Plex-Device: Linux' \
        "https://plex.tv/api/claim/exchange?token=${PLEX_CLAIM}")"
    token="$(echo "$loginInfo" | sed -n 's/.*<authentication-token>\(.*\)<\/authentication-token>.*/\1/p')"

    if [ "$token" ]; then
        echo "Token obtained successfully"
        setPref "PlexOnlineToken" "${token}"
    fi
fi

test -n "${ADVERTISE_IP}"       && setPref "customConnections" "${ADVERTISE_IP}"
test -n "${ALLOWED_NETWORKS}"   && setPref "allowedNetworks" "${ALLOWED_NETWORKS}"
test -n "${DISABLE_REMOTE_SEC}" && setPref "disableRemoteSecurity" "1"
