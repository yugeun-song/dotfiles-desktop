#!/usr/bin/env bash
# Tests quickshell/bar/scripts/weather.sh's place against a temporary
# XDG_STATE_HOME and XDG_CACHE_HOME, with a stand-in curl that answers
# Open-Meteo's two hosts from fixtures and logs what it was asked: the
# search, a pick kept or refused, the place every later run then uses, the
# environment over it, a file anything else wrote, and Seoul back.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$REPO/quickshell/bar/scripts/weather.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP  weather: jq is not installed"; exit 0; }
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
export XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache"
PLACE="$WORK/state/quickshell/bar/weather-place"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_LOG"
case "$*" in
    *geocoding-api.open-meteo.com*)
        [ -f "$CURL_FAIL" ] && exit 6
        query=$(cat)
        printf 'stdin: %s\n' "$query" >> "$CURL_LOG"
        case "$query" in
            zz*) echo '{"generationtime_ms": 0.1}' ;;
            *) echo '{"results": [{"name": "Busan", "admin1": "Busan", "country": "South Korea", "latitude": 35.10168, "longitude": 129.03004, "timezone": "Asia/Seoul"}, {"name": "Busan-si", "latitude": null, "longitude": 1}]}' ;;
        esac ;;
    *api.open-meteo.com*)
        echo '{"current": {"temperature_2m": 20.4, "relative_humidity_2m": 50, "apparent_temperature": 19.6, "is_day": 1, "weather_code": 0, "wind_speed_10m": 3, "wind_direction_10m": 0}, "daily": {"time": ["2026-10-27"], "weather_code": [0], "temperature_2m_max": [22], "temperature_2m_min": [12]}}' ;;
    *) exit 7 ;;
esac
EOF
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH" CURL_LOG="$WORK/curl.log" CURL_FAIL="$WORK/curl-fails"

failed=0
passed=0
ok() {
    if [[ "$2" == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL  weather: %s: got [%s], want [%s]\n' "$1" "$2" "$3"
    fi
}
run() { "$SCRIPT" "$@" 2>/dev/null; }
asked() { grep -c -F -- "$1" "$CURL_LOG"; }

out=$(run --search Busan)
ok "search: the places, one with no coordinates left out" "$(jq -c '[.results[].name]' <<<"$out")" '["Busan"]'
ok "search: the name asked comes back" "$(jq -r .query <<<"$out")" "Busan"
ok "search: region, country, coordinates and zone" \
    "$(jq -c '.results[0] | [.admin, .country, .lat, .lon, .tz]' <<<"$out")" '["Busan","South Korea",35.10168,129.03004,"Asia/Seoul"]'
ok "search: over https only, the name encoded from stdin" \
    "$(asked "--proto =https --proto-redir =https")$(asked "--data-urlencode name@-")$(asked "stdin: Busan")" "111"
ok "search: the name in no argument list" "$(grep -v '^stdin: ' "$CURL_LOG" | grep -c Busan)" 0
ok "search: the bar's way, the name in the environment" "$(WEATHER_QUERY=Busan run --search | jq -r .query)" "Busan"
: > "$CURL_LOG"
ok "search: one letter" "$(run --search B)" '{"query":"B","results":[]}'
ok "search: asks nothing of the network" "$(wc -l < "$CURL_LOG")" 0
ok "search: nothing found" "$(run --search zzqx | jq -c .results)" "[]"
touch "$CURL_FAIL"
ok "search: no network" "$(run --search Busan | jq -r .error)" "unreachable"
rm -f "$CURL_FAIL"

ok "no place kept: Seoul" "$(run --bar | jq -r '.place + " " + .source')" "Seoul default"
ok "no place kept: Seoul's centre asked" "$(asked "latitude=37.5665&longitude=126.9780")" 1

run --set Busan 35.10168 129.03004 Asia/Seoul; ok "set" "$?" 0
ok "set: the file" "$(jq -c . "$PLACE")" '{"name":"Busan","lat":35.10168,"lon":129.03004,"tz":"Asia/Seoul"}'
ok "set: the bar's place" "$(run --bar | jq -r '[.place, .source, .lat, .lon] | map(tostring) | join(" ")')" \
    "Busan saved 35.10168 129.03004"
ok "set: its coordinates and zone asked" "$(asked "latitude=35.10168&longitude=129.03004")$(asked "timezone=Asia/Seoul")" "12"

run --set Nowhere 91 0 UTC; ok "set: a latitude past the pole" "$?" 2
run --set X 1 181 UTC; ok "set: a longitude past the date line" "$?" 2
run --set X north 1 UTC; ok "set: a latitude that is no number" "$?" 2
run --set "" 1 1 UTC; ok "set: no name" "$?" 2
run --set X 1 1 'Asia/Seoul&x=1'; ok "set: a zone that would reach the query" "$?" 2
ok "set: a refused one leaves the place" "$(jq -r .name "$PLACE")" "Busan"
run --set "$(printf 'Bu\tsan\001')" 35.1 129.0 Asia/Seoul
ok "set: control characters dropped" "$(jq -r .name "$PLACE")" "Busan"
run --set "$(printf 'x%.0s' {1..80})" 35.1 129.0 Asia/Seoul
ok "set: a long name cut" "$(jq -r '.name | length' "$PLACE")" 60

ok "the environment over the kept place" \
    "$(WEATHER_LAT=37.4563 WEATHER_LON=126.7052 WEATHER_NAME=Incheon run --bar | jq -r '.place + " " + .source')" "Incheon env"

printf 'not json\n' > "$PLACE"
ok "a file that is no JSON: Seoul" "$(run --bar | jq -r '.place + " " + .source')" "Seoul default"
printf '{"name":"X","lat":100,"lon":1,"tz":"UTC"}\n' > "$PLACE"
ok "a file out of range: Seoul" "$(run --bar | jq -r .source)" "default"
# The zone is meant literally: a command substitution that must stay text.
# shellcheck disable=SC2016
printf '{"name":"X","lat":1,"lon":1,"tz":"$(reboot)"}\n' > "$PLACE"
ok "a file whose zone is no zone: Seoul" "$(run --bar | jq -r .source)" "default"

run --set Busan 35.10168 129.03004 Asia/Seoul
run --reset; ok "reset" "$?" 0
ok "reset: the file goes" "$([[ -e "$PLACE" ]] && echo kept || echo gone)" "gone"
ok "reset: Seoul again" "$(run --bar | jq -r '.place + " " + .source')" "Seoul default"

if (( failed == 0 )); then
    echo "PASS  weather: $passed checks"
    exit 0
fi
exit 1
