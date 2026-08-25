#!/usr/bin/env bash
#
# Weather lookup. Usable from a shell or called by a desktop shell widget.
#
# The location is pinned to fixed coordinates. Neither GPS nor IP-based
# geolocation is used. Data comes from Open-Meteo, which needs no API key.
# Coordinates are passed explicitly, so there is no room for the service to
# infer a location.
#
# To use a different city, edit the three variables below, or override them
# through the environment:
#   WEATHER_LAT=35.1796 WEATHER_LON=129.0756 WEATHER_NAME=Busan weather.sh
#
# Output modes
#   (default)  one-line summary
#   --json     raw JSON, for a shell widget to parse
#   --full     multi-line detail with a 3-day forecast
#   --icon     icon glyph only, for a status bar
#   --bar      one line of compact JSON, for the status bar shell to parse
#
# Requires: curl, jq
#
set -uo pipefail

for dep in curl jq; do
    command -v "$dep" >/dev/null 2>&1 || { echo "weather.sh: $dep is required" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Location. This is the only block that needs editing.
# Look coordinates up at https://open-meteo.com/en/docs (geocoding section).
# ---------------------------------------------------------------------------
WEATHER_LAT="${WEATHER_LAT:-37.5665}"
WEATHER_LON="${WEATHER_LON:-126.9780}"
WEATHER_NAME="${WEATHER_NAME:-Seoul}"
WEATHER_TZ="${WEATHER_TZ:-Asia/Seoul}"

# Kept below the status bar's 15-minute poll. At exactly 15 the cache is still
# a few seconds short of expiring when the next tick arrives, so that tick is
# served from cache and the reading only refreshes every 30 minutes.
CACHE_TTL="${WEATHER_CACHE_TTL:-600}"   # 10 minutes
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/weather"
CACHE_FILE="$CACHE_DIR/${WEATHER_LAT}_${WEATHER_LON}.json"

mkdir -p "$CACHE_DIR"

API="https://api.open-meteo.com/v1/forecast"
PARAMS="latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}"
PARAMS+="&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_direction_10m"
PARAMS+="&daily=weather_code,temperature_2m_max,temperature_2m_min"
PARAMS+="&timezone=${WEATHER_TZ}&forecast_days=3"

fetch() {
    curl -fsSL --max-time 10 "${API}?${PARAMS}"
}

cache_mtime() {
    stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0
}

cache_fresh() {
    [[ -s "$CACHE_FILE" ]] || return 1
    local age=$(( $(date +%s) - $(cache_mtime) ))
    (( age < CACHE_TTL ))
}

# A cache truncated by a killed run is still non-empty with a fresh mtime, so
# age alone does not say the file is usable.
cache_read() {
    local cached
    cached=$(cat "$CACHE_FILE" 2>/dev/null) || return 1
    printf '%s' "$cached" | jq -e '.current' >/dev/null 2>&1 || return 1
    printf '%s' "$cached"
}

# Sets $json and $FETCHED. FETCHED is when the reading it returns was obtained,
# so a consumer can tell a stale cache from a live answer; a live body is timed
# here rather than by the cache mtime, which stays behind when the cache write
# is skipped.
get_json() {
    if cache_fresh && json=$(cache_read); then
        FETCHED=$(cache_mtime)
        return 0
    fi
    local body tmp
    body=$(fetch)
    if [[ -n "$body" ]] && printf '%s' "$body" | jq -e '.current' >/dev/null 2>&1; then
        # Write through a temporary file so a run that dies mid-write leaves
        # the previous cache in place instead of a partial one.
        if tmp=$(mktemp "$CACHE_DIR/.wx.XXXXXX" 2>/dev/null); then
            printf '%s' "$body" > "$tmp" && mv "$tmp" "$CACHE_FILE" || rm -f "$tmp"
        fi
        json=$body
        FETCHED=$(date +%s)
        return 0
    fi
    # On a failed fetch, fall back to a stale cache so the last known value
    # still shows while the network is down.
    if json=$(cache_read); then
        FETCHED=$(cache_mtime)
        return 0
    fi
    return 1
}

# WMO weather code to text. Table follows the Open-Meteo documentation.
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

# Icon glyphs. A Nerd Font is in use, so these are present.
# When is_day is 0 the clear/partly-cloudy cases switch to night glyphs.
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
get_json || { echo "weather.sh: fetch failed and no usable cache at $CACHE_FILE" >&2; exit 1; }

code=$(printf '%s' "$json" | jq -r '.current.weather_code')
isday=$(printf '%s' "$json" | jq -r '.current.is_day')
temp=$(printf '%s' "$json" | jq -r '.current.temperature_2m | round')
feels=$(printf '%s' "$json" | jq -r '.current.apparent_temperature | round')

case "${1:-}" in
    --json)
        printf '%s\n' "$json"
        ;;
    --icon)
        wmo_icon "$code" "$isday"
        ;;
    --bar)
        # One line, so a stream parser split on newlines receives it whole.
        printf '%s' "$json" | jq -c --arg place "$WEATHER_NAME" --argjson fetched "$FETCHED" '{
            place:    $place,
            fetched:  $fetched,
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
