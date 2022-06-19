CONFIG_DIR="${CONFIG_DIR:-/config}"
PREF_FILE="${PREF_FILE:-"$CONFIG_DIR/Preferences.xml"}"

getPref() {
    xmlstarlet sel -T -t -m "/Preferences" -v "@$1" -n "${PREF_FILE}"
}
setPref() {
    count="$(xmlstarlet sel -t -v "count(/Preferences/@$1)" "${PREF_FILE}")"
    if [ $((count + 0)) -gt 0 ]; then
        xmlstarlet ed --inplace --update "/Preferences/@$1" -v "$2" "${PREF_FILE}" 2>/dev/null
    else
        xmlstarlet ed --inplace --insert "/Preferences"  --type attr -n "$1" -v "$2" "${PREF_FILE}" 2>/dev/null
    fi
}
