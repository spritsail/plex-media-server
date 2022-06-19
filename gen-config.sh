#!/bin/sh
set -e

# Contains getPref/setPref and PREF_FILE vars
. plex-util.sh

# Create a default config file allowing external access
printf "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<Preferences />" > "${PREF_FILE}"

# Enforced defaults. These can be changed manually afterwards.
setPref "EnableIPv6" "1"
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
    clientId="$(printf %s "${serial}- Plex Media Server" | sha1sum | cut -b 1-40)"
    setPref "ProcessedMachineIdentifier" "${clientId}"
fi

# Claiming the PlexOnlineToken is now done in entrypoint on every boot
# It can also be triggered manually at any time by running
#           $ claim-server.sh --load-client-id --save

if [ -n "${ADVERTISE_IP}" ]; then       setPref "customConnections" "${ADVERTISE_IP}"; fi
if [ -n "${ALLOWED_NETWORKS}" ]; then   setPref "allowedNetworks" "${ALLOWED_NETWORKS}"; fi
if [ -n "${DISABLE_REMOTE_SEC}" ]; then setPref "disableRemoteSecurity" "1"; fi
