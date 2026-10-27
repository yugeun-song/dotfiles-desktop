#!/usr/bin/env bash
# Weather from Open-Meteo (no API key) for one place; no geolocation. The
# place is the one the bar's place panel kept (modules/WeatherPanel.qml), in
# the bar's state directory and never in the repository; else Seoul, the
# default. WEATHER_LAT and WEATHER_LON in the environment override both:
#   WEATHER_LAT=35.1796 WEATHER_LON=129.0756 WEATHER_NAME=Busan weather.sh
#
#   (default)  one-line summary
#   --json     raw JSON
#   --full     multi-line detail with a 3-day forecast
#   --icon     icon glyph only
#   --bar      one line of compact JSON, for the bar
#   --refresh  ask the network even when the cache is fresh; a failed fetch
#              still falls back to the cache
#   --search NAME          the places by that name, one line of JSON
#                          (Open-Meteo's geocoding, on GeoNames' data);
#                          the bar gives NAME in WEATHER_QUERY instead
#   --set NAME LAT LON TZ  keep that place for every later run
#   --reset                forget it: Seoul again
#
# Requires: curl, jq

set -uo pipefail

for dep in curl jq; do
    command -v "$dep" >/dev/null 2>&1 || { echo "weather.sh: $dep is required" >&2; exit 1; }
done

# The picked place, beside the bar's other choices (services/Paths.qml).
PLACE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/bar/weather-place"
GEOCODE="https://geocoding-api.open-meteo.com/v1/search"

# A place from four strings, or nothing when they make none. The file is
# checked on every read as well, since anything could have written it: the
# name loses control characters and stays short, and the zone must look like
# an IANA name, as it goes into the query string.
place_of() {
    jq -nc --arg name "$1" --arg lat "$2" --arg lon "$3" --arg tz "$4" '
        ($lat | tonumber? // null) as $la | ($lon | tonumber? // null) as $lo
        | ($name | gsub("[[:cntrl:]]"; "") | .[0:60]) as $n
        | select($la != null and $lo != null and $la >= -90 and $la <= 90
                 and $lo >= -180 and $lo <= 180 and ($n | length) > 0
                 and ($tz | test("^[A-Za-z0-9_+/-]{1,64}$")))
        | {name: $n, lat: $la, lon: $lo, tz: $tz}'
}

read_place() {
    local fields name lat lon tz
    [[ -s "$PLACE_FILE" ]] || return 1
    fields=$(jq -r 'select(type == "object") | [.name, .lat, .lon, .tz] | map(tostring) | @tsv' \
        "$PLACE_FILE" 2>/dev/null) || return 1
    IFS=$'\t' read -r name lat lon tz <<<"$fields"
    place_of "$name" "$lat" "$lon" "$tz"
}

# The places by that name as one line, {query, results: [{name, admin,
# country, lat, lon, tz}]} or {query, error}. The query comes back with
# them, so the bar can drop an answer to a name it no longer asks for. It
# reaches curl on stdin, never in an argument list any local process could
# read, and so does it come from the bar (WEATHER_QUERY).
search_places() {
    local query=${1:0:100} body
    if (( ${#query} < 2 )); then
        jq -nc --arg q "$1" '{query: $q, results: []}'
        return
    fi
    if ! body=$(printf '%s' "$query" | curl -fsSL --proto '=https' --proto-redir '=https' --max-redirs 3 \
            --max-time 10 --max-filesize 1048576 --get --data-urlencode "name@-" --data count=8 \
            --data language=en --data format=json "$GEOCODE"); then
        jq -nc --arg q "$1" '{query: $q, error: "unreachable"}'
        return
    fi
    printf '%s' "$body" | jq -c --arg q "$1" '{query: $q, results: [.results[]? | {
            name: (.name // ""), admin: (.admin1 // ""), country: (.country // ""),
            lat: .latitude, lon: .longitude, tz: (.timezone // "auto")}
        | select((.lat | type) == "number" and (.lon | type) == "number" and .name != "")]}' \
        2>/dev/null || jq -nc --arg q "$1" '{query: $q, error: "unreadable"}'
}

case "${1:-}" in
    --search)
        search_places "${WEATHER_QUERY-${2:-}}"
        exit 0
        ;;
    --set)
        place=$(place_of "${2:-}" "${3:-}" "${4:-}" "${5:-}")
        [[ -n "$place" ]] || { echo "weather.sh: not a place" >&2; exit 2; }
        dir=${PLACE_FILE%/*}
        mkdir -p "$dir" && tmp=$(mktemp "$dir/.weather-place.XXXXXX") || exit 1
        if printf '%s\n' "$place" > "$tmp" && mv -f "$tmp" "$PLACE_FILE"; then
            exit 0
        fi
        rm -f "$tmp"
        exit 1
        ;;
    --reset)
        rm -f -- "$PLACE_FILE"
        exit 0
        ;;
esac

MODE=""
REFRESH=0
for arg in "$@"; do
    if [[ "$arg" == --refresh ]]; then
        REFRESH=1
    elif [[ -z "$MODE" ]]; then
        MODE="$arg"
    fi
done

# Location: the environment's, else the saved place, else Seoul's centre as a
# geocoder gives it (never a home's: the repository is public).
PLACE_SOURCE="default"
if [[ -n "${WEATHER_LAT:-}" && -n "${WEATHER_LON:-}" ]]; then
    PLACE_SOURCE="env"
elif place=$(read_place) && [[ -n "$place" ]]; then
    IFS=$'\t' read -r WEATHER_NAME WEATHER_LAT WEATHER_LON WEATHER_TZ \
        < <(printf '%s' "$place" | jq -r '[.name, .lat, .lon, .tz] | map(tostring) | @tsv')
    PLACE_SOURCE="saved"
fi
WEATHER_LAT="${WEATHER_LAT:-37.5665}"
WEATHER_LON="${WEATHER_LON:-126.9780}"
WEATHER_NAME="${WEATHER_NAME:-Seoul}"
WEATHER_TZ="${WEATHER_TZ:-Asia/Seoul}"

# Below the bar's 15-minute poll; at exactly 15 every other tick hits the cache.
CACHE_TTL="${WEATHER_CACHE_TTL:-600}"   # 10 minutes
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/weather"
CACHE_FILE="$CACHE_DIR/${WEATHER_LAT}_${WEATHER_LON}.json"

mkdir -p "$CACHE_DIR"

API="https://api.open-meteo.com/v1/forecast"
PARAMS="latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}"
PARAMS+="&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_direction_10m"
PARAMS+="&daily=weather_code,temperature_2m_max,temperature_2m_min"
PARAMS+="&timezone=${WEATHER_TZ}&forecast_days=3"

# https only, redirects included: the query string carries the coordinates.
fetch() {
    curl -fsSL --proto '=https' --proto-redir '=https' --max-redirs 3 \
        --max-time 10 --max-filesize 1048576 "${API}?${PARAMS}"
}

cache_mtime() {
    stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0
}

# A cache stamped in the future is not fresh: one of the two clocks was wrong.
# After a hard power-off the RTC restarts at the firmware's build date, and the
# clock is only right again once NTP answers.
cache_fresh() {
    [[ -s "$CACHE_FILE" ]] || return 1
    local age=$(( $(date +%s) - $(cache_mtime) ))
    (( age >= 0 && age < CACHE_TTL ))
}

# Validate content: a truncated cache can still look fresh.
cache_read() {
    local cached
    cached=$(cat "$CACHE_FILE" 2>/dev/null) || return 1
    printf '%s' "$cached" | jq -e '.current' >/dev/null 2>&1 || return 1
    printf '%s' "$cached"
}

# Sets $json, $FETCHED (when the reading was obtained) and $LIVE (0 when the
# fetch failed and an expired cache stands in). A live body uses now, not the
# cache mtime, since the cache write may be skipped. The bar retries on LIVE=0
# rather than judging by FETCHED, which is only as right as the clock.
get_json() {
    if (( ! REFRESH )) && cache_fresh && json=$(cache_read); then
        FETCHED=$(cache_mtime)
        LIVE=1
        return 0
    fi
    local body tmp
    body=$(fetch)
    if [[ -n "$body" ]] && printf '%s' "$body" | jq -e '.current' >/dev/null 2>&1; then
        # Atomic replace.
        if tmp=$(mktemp "$CACHE_DIR/.wx.XXXXXX" 2>/dev/null); then
            if ! { printf '%s' "$body" > "$tmp" && mv "$tmp" "$CACHE_FILE"; }; then
                rm -f "$tmp"
            fi
        fi
        json=$body
        FETCHED=$(date +%s)
        LIVE=1
        return 0
    fi
    # Fetch failed: serve the stale cache.
    if json=$(cache_read); then
        FETCHED=$(cache_mtime)
        LIVE=0
        return 0
    fi
    return 1
}

# WMO weather code to text, per the Open-Meteo docs.
wmo_desc() {
    case "$1" in
        0)        echo "Clear" ;;
        1)        echo "Mostly clear" ;;
        2)        echo "Partly cloudy" ;;
        3)        echo "Overcast" ;;
        45|48)    echo "Fog" ;;
        51|53|55) echo "Drizzle" ;;
        56|57)    echo "Freezing drizzle" ;;
        61)       echo "Light rain" ;;
        63)       echo "Rain" ;;
        65)       echo "Heavy rain" ;;
        66|67)    echo "Freezing rain" ;;
        71)       echo "Light snow" ;;
        73)       echo "Snow" ;;
        75)       echo "Heavy snow" ;;
        77)       echo "Snow grains" ;;
        80|81|82) echo "Rain showers" ;;
        85|86)    echo "Snow showers" ;;
        95)       echo "Thunderstorm" ;;
        96|99)    echo "Thunderstorm with hail" ;;
        *)        echo "Unknown" ;;
    esac
}

# Nerd Font glyphs; clear/partly-cloudy switch to night variants when is_day=0.
wmo_icon() {
    local code="$1" day="${2:-1}"
    case "$code" in
        0)        [[ "$day" == 1 ]] && echo "󰖙" || echo "󰖔" ;;
        1|2)      [[ "$day" == 1 ]] && echo "󰖕" || echo "󰼱" ;;
        3)        echo "󰖐" ;;
        45|48)    echo "󰖑" ;;
        51|53|55|56|57) echo "󰖗" ;;
        61|63|65|66|67) echo "󰖖" ;;
        71|73|75|77)    echo "󰖘" ;;
        80|81|82) echo "󰖖" ;;
        85|86)    echo "󰖘" ;;
        95|96|99) echo "󰖓" ;;
        *)        echo "󰖐" ;;
    esac
}

json=""
FETCHED=0
LIVE=0
# Not the cache's path, which carries the coordinates: the bar logs this
# line, and the journal keeps it.
get_json || { echo "weather.sh: fetch failed and no usable cache" >&2; exit 1; }

code=$(printf '%s' "$json" | jq -r '.current.weather_code')
isday=$(printf '%s' "$json" | jq -r '.current.is_day')
temp=$(printf '%s' "$json" | jq -r '.current.temperature_2m | round')
feels=$(printf '%s' "$json" | jq -r '.current.apparent_temperature | round')

case "$MODE" in
    --json)
        printf '%s\n' "$json"
        ;;
    --icon)
        wmo_icon "$code" "$isday"
        ;;
    --bar)
        # Single line for the bar's line parser.
        printf '%s' "$json" | jq -c --arg place "$WEATHER_NAME" --arg source "$PLACE_SOURCE" \
            --arg lat "$WEATHER_LAT" --arg lon "$WEATHER_LON" --argjson fetched "$FETCHED" \
            --argjson live "$( (( LIVE )) && echo true || echo false )" '{
            place:    $place,
            source:   $source,
            lat:      ($lat | tonumber? // null),
            lon:      ($lon | tonumber? // null),
            fetched:  $fetched,
            live:     $live,
            code:     .current.weather_code,
            temp:     (.current.temperature_2m | round),
            feels:    (.current.apparent_temperature | round),
            humidity: .current.relative_humidity_2m,
            wind:     .current.wind_speed_10m,
            day:      .current.is_day,
            today:    { min: (.daily.temperature_2m_min[0] | round), max: (.daily.temperature_2m_max[0] | round) }
        }'
        echo
        ;;
    --full)
        hum=$(printf '%s' "$json" | jq -r '.current.relative_humidity_2m')
        wind=$(printf '%s' "$json" | jq -r '.current.wind_speed_10m')
        printf '%s\n' "$WEATHER_NAME"
        printf 'temp      %s C (feels like %s C)\n' "$temp" "$feels"
        printf 'sky       %s\n' "$(wmo_desc "$code")"
        printf 'humidity  %s%%\n' "$hum"
        printf 'wind      %s km/h\n' "$wind"
        printf '\nforecast\n'
        printf '%s' "$json" | jq -r '
            .daily as $d |
            range(0; ($d.time | length)) as $i |
            "  \($d.time[$i])  \($d.temperature_2m_min[$i] | round) to \($d.temperature_2m_max[$i] | round) C  code \($d.weather_code[$i])"
        '
        ;;
    *)
        printf '%s %sC  %s  feels %sC\n' \
            "$(wmo_icon "$code" "$isday")" "$temp" "$(wmo_desc "$code")" "$feels"
        ;;
esac
