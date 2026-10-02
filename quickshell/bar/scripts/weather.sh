#!/usr/bin/env bash
# Weather from Open-Meteo (no API key) for fixed coordinates; no geolocation.
# Change the city by editing the location block below or via the environment:
#   WEATHER_LAT=35.1796 WEATHER_LON=129.0756 WEATHER_NAME=Busan weather.sh
#
# Output modes
#   (default)  one-line summary
#   --json     raw JSON, for a shell widget to parse
#   --full     multi-line detail with a 3-day forecast
#   --icon     icon glyph only, for a status bar
#   --bar      one line of compact JSON, for the status bar shell to parse
#
# Option
#   --refresh  ask the network even when the cache is fresh (the bar's click);
#              a failed fetch still falls back to the cache
#
# Requires: curl, jq
#
set -uo pipefail

for dep in curl jq; do
    command -v "$dep" >/dev/null 2>&1 || { echo "weather.sh: $dep is required" >&2; exit 1; }
done

MODE=""
REFRESH=0
for arg in "$@"; do
    if [[ "$arg" == --refresh ]]; then
        REFRESH=1
    elif [[ -z "$MODE" ]]; then
        MODE="$arg"
    fi
done

# Location. Coordinates: https://open-meteo.com/en/docs (geocoding section).
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
        --max-time 10 "${API}?${PARAMS}"
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
            printf '%s' "$body" > "$tmp" && mv "$tmp" "$CACHE_FILE" || rm -f "$tmp"
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
get_json || { echo "weather.sh: fetch failed and no usable cache at $CACHE_FILE" >&2; exit 1; }

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
        printf '%s' "$json" | jq -c --arg place "$WEATHER_NAME" --argjson fetched "$FETCHED" \
            --argjson live "$( (( LIVE )) && echo true || echo false )" '{
            place:    $place,
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
