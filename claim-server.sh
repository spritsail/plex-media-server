#!/bin/sh
set -e

# Contains getPref/setPref and PREF_FILE vars
. plex-util.sh

opts=$(getopt -n "$0" -l save -l token: -l client-id: -l load-client-id -- st:c:l "$@") || exit 1
eval set -- "$opts"
while true; do
    case "$1" in
        -s|--save) save=true; shift;;
        -t|--token) claimToken="$2"; shift 2;;
        -c|--client-id) clientId="$2"; shift 2;;
        -l|--load-client-id) clientId="$(getPref "ProcessedMachineIdentifier")"; shift;;
        --)	shift; break;;
        *)	echo 'Error: getopt'; exit 1;;
    esac
done

claimToken="${PLEX_CLAIM:-$claimToken}"
clientId="${PLEX_CLIENT_ID:-$clientId}"

if [ -z "${claimToken}" ]; then
    >&2 echo "Error: \$PLEX_CLAIM or --token required to claim a server"
    >&2 echo "       Obtain one from https://plex.tv/claim"
    exit 2
fi
if [ -z "${clientId}" ]; then
    >&2 echo "Error: \$PLEX_CLIENT_ID or --client-id required to claim a server"
    >&2 echo "       This is found as 'ProcessedMachineIdentifier' in Preferences.xml"
    >&2 echo "       Calling this script with --load-client-id will attempt to populate this for you"
    exit 3
fi

>&2 echo "Attempting to obtain server token from claim token"
loginInfo="$(curl -X POST \
    -H "X-Plex-Client-Identifier: ${clientId}" \
    -H "X-Plex-Product: Plex Media Server" \
    -H "X-Plex-Version: 1.1" \
    -H "X-Plex-Provides: server" \
    -H "X-Plex-Platform: Linux" \
    -H "X-Plex-Platform-Version: 1.0" \
    -H "X-Plex-Device-Name: PlexMediaServer" \
    -H "X-Plex-Device: Linux" \
    "https://plex.tv/api/claim/exchange?token=${claimToken}"
)"

authtoken="$(echo "$loginInfo" | sed -n 's/.*<authentication-token>\(.*\)<\/authentication-token>.*/\1/p')"

if [ -z "$authtoken" ]; then
    >&2 echo "Error: Unable to obtain authentication token from Plex"
    exit 10
else
    >&2 echo "Token obtained successfully"
fi

if [ -n "$save" ]; then
    setPref "PlexOnlineToken" "${authtoken}"
else
    printf "%s" "$authtoken"
fi

