#!/usr/bin/env bash

# HOW TO USE:
# 1. Add this script into your waybar, as an executable script obviously. (If you don't know how to do: sudo chmod +x lyric_bars.sh)
# 2. Next up is add in this as your module for the script. (Make sure to change username back to your actual directory name.)
# "custom/lyrics": {
#         "exec": "/home/username/.config/waybar/lyric_bars.sh",
#        "interval": 0.5, // Time for execute so feel free to turn it down with the cost of delay.
#         "tooltip": true,
#         "on-click": "/home/username/.config/waybar/lyric_bars.sh right",
#         "on-click-right": "/home/username/.config/waybar/lyric_bars.sh right",
#         "on-click-middle": "/home/username/.config/waybar/lyric_bars.sh middle",
#         "on-click-left": "/home/username/.config/waybar/lyric_bars.sh left",
#         "signal": 10,
#         "max-length": 80, // You can also modify it to be longer or shorter text display.
#         "smooth-scrolling-threshold": 1,
#         "exec-on-event": true,
# Don't forget to add it in to your modules-left, modules-right, modules-center to display it.
# 3. Extra step: You can configure the styles.css by calling #custom/lyrics {} to change how it display as you want.
# 4. Profit.
# EXTRA NOTE: You can change the lcr file that it generated so that you can add in your own lyrics or use lrcget and upload your own version of the subtitle you want [of course it has to be in lrc type not vtt or srt, at least you will have to convert it.]
# Also feel free to edit and improve my code whatever you want. Since It's just a crappy code I slapped together to just read subtitle whenever I don't watch youtube video directly anyway,

# Configuration
CACHE_DIR="/home/$USER/Documents/lrclib_lyrics" # Your directory to save config and lyrics file.
mkdir -p "$CACHE_DIR"
OFFSET=0.5 # Early offset config. Change this as much as you want to fix delay.
SELECTED_INDEX_FILE="$CACHE_DIR/.selected_index" # Your directory to save config and lyrics file.
OPTIONS_FILE="$CACHE_DIR/.options" # Your directory to save config and lyrics file.
ERROR_LOG="$CACHE_DIR/error.log" # Your directory to save config and lyrics file.
API_RESPONSE_LOG="$CACHE_DIR/api_response.json" # Your directory to save config and lyrics file.
CURRENT_SONG_FILE="$CACHE_DIR/current_song.txt" # Your directory to save config and lyrics file.
SELECTION_TIMEOUT=15 #Time for your selection when there are multiple result.
LAST_FETCH_FILE="$CACHE_DIR/.last_fetch" # Your directory to save config and lyrics file.
LAST_CLICK_FILE="$CACHE_DIR/.last_click" # Your directory to save config and lyrics file.
CLICK_DEBOUNCE=1 # Click option when on the selection part.
SELECTION_CONFIRMED_FILE="$CACHE_DIR/.selection_confirmed" # Your directory to save config and lyrics file.

# Ensure UTF-8 encoding
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$ERROR_LOG"
}

# Clean title function (preserves "/" for splitting)
clean_title() {
    local title="$1"
    title=$(echo "$title" | sed -E 's/\([^)]*\)//g; s/\[[^]]*\]//g; s/【[^】]*】//g; s/ (MV|VIDEO|OFFICIAL|feat\.?|ft\.?|MUSIC)//ig; s/[[:space:]]*$//')
    echo "$title"
}

# Get song position
get_position() {
    local pos
    pos=$(playerctl metadata --format '{{duration(position)}}' 2>/dev/null || echo "0:00")
    local min sec
    min=$(echo "$pos" | cut -d: -f1)
    sec=$(echo "$pos" | cut -d: -f2)
    echo "$min * 60 + $sec + $OFFSET" | bc
}

# Fetch lyrics with secondary search logic
fetch_lyrics() {
    local title="$1"
    local cache_file="$2"
    local api_response_log="$API_RESPONSE_LOG"
    local current_time
    current_time=$(date +%s)

    # URL-encode the title to handle non-ASCII characters
    local encoded_title
    encoded_title=$(printf '%s' "$title" | jq -Rr @uri)
    log "Encoded title for API query: $encoded_title"

    # Initial search with full title
    local url="https://lrclib.net/api/search?q=$encoded_title"
    log "Fetching lyrics from: $url"
    local response
    response=$(curl -s --fail "$url" -H "Accept: application/json" 2>>"$ERROR_LOG")
    if [ $? -eq 0 ]; then
        echo "$response" > "$api_response_log"
        log "API response saved to: $api_response_log"
        local has_lyrics
        has_lyrics=$(echo "$response" | jq -e '.[] | select(.syncedLyrics != null or .plainLyrics != null)' 2>/dev/null)
        if [ -n "$has_lyrics" ]; then
            echo "$current_time" > "$LAST_FETCH_FILE"
            log "Lyrics fetched successfully for title: $title"
            return 0
        fi
    fi

    # Secondary search if title contains "-" or "/"
    if [[ "$title" =~ [-/] ]]; then
        local parts
        IFS='-/ ' read -ra parts <<< "$title"
        for part in "${parts[@]}"; do
            part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$part" ]; then
                local encoded_part
                encoded_part=$(printf '%s' "$part" | jq -Rr @uri)
                url="https://lrclib.net/api/search?q=$encoded_part"
                log "Secondary search for part: $part"
                response=$(curl -s --fail "$url" -H "Accept: application/json" 2>>"$ERROR_LOG")
                if [ $? -eq 0 ]; then
                    has_lyrics=$(echo "$response" | jq -e '.[] | select(.syncedLyrics != null or .plainLyrics != null)' 2>/dev/null)
                    if [ -n "$has_lyrics" ]; then
                        echo "$response" > "$api_response_log"
                        echo "$current_time" > "$LAST_FETCH_FILE"
                        log "Lyrics fetched successfully for part: $part"
                        return 0
                    fi
                fi
            fi
        done
    fi

    log "No valid lyrics found after secondary search for title: $title"
    echo "No lyrics found" > "$cache_file"
    return 1
}

# Save lyrics to file
save_lyrics_to_file() {
    local selected_index="$1"
    local cache_file="$2"
    local synced_lyrics
    synced_lyrics=$(jq -r ".[$selected_index].syncedLyrics" "$API_RESPONSE_LOG" 2>/dev/null)
    log "Synced lyrics for index=$selected_index: $synced_lyrics"

    if [ "$synced_lyrics" != "null" ] && [ -n "$synced_lyrics" ]; then
        echo "$synced_lyrics" > "$cache_file"
        log "Saved synced lyrics to: $cache_file"
        return 0
    fi

    local plain_lyrics
    plain_lyrics=$(jq -r ".[$selected_index].plainLyrics" "$API_RESPONSE_LOG" 2>/dev/null)
    log "Falling back to plain lyrics: $plain_lyrics"
    if [ "$plain_lyrics" != "null" ] && [ -n "$plain_lyrics" ]; then
        echo "$plain_lyrics" > "$cache_file"
        log "Saved plain lyrics to: $cache_file"
        return 0
    fi

    log "No lyrics to save for index=$selected_index"
    echo "No lyrics found" > "$cache_file"
    return 1
}

# Parse options for multiple lyric results
parse_options() {
    jq -r '.[] | select(.syncedLyrics != null) | "\(.name) [\(.duration)]"' "$API_RESPONSE_LOG" 2>/dev/null | tee "$OPTIONS_FILE"
}

# Get selected title
get_selected_title() {
    local selected_index
    selected_index=$(cat "$SELECTED_INDEX_FILE" 2>/dev/null || echo "0")
    awk -v idx="$selected_index" 'NR==idx+1' "$OPTIONS_FILE" 2>/dev/null || echo "No title selected"
}

# Handle click
handle_click() {
    local click_type="$1"
    local options_count="$2"
    local current_index
    current_index=$(cat "$SELECTED_INDEX_FILE" 2>/dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    local last_click
    last_click=$(cat "$LAST_CLICK_FILE" 2>/dev/null || echo "0")

    if [ "$options_count" -eq 1 ]; then
        log "Click ignored: only one option available, already confirmed"
        echo "$(get_selected_title)"
        return 0
    fi

    if [ $((current_time - last_click)) -lt $CLICK_DEBOUNCE ]; then
        log "Click ignored (debounce): type=$click_type, current_index=$current_index"
        echo "$(get_selected_title)"
        return 0
    fi
    echo "$current_time" > "$LAST_CLICK_FILE"

    log "Click detected: type=$click_type, current_index=$current_index, options_count=$options_count"

    case "$click_type" in
        left)
            new_index=$((current_index - 1))
            [ $new_index -lt 0 ] && new_index=$((options_count - 1))
            ;;
        right)
            new_index=$((current_index + 1))
            [ $new_index -ge $options_count ] && new_index=0
            ;;
        middle)
            touch "$SELECTION_CONFIRMED_FILE"
            log "Selection confirmed: index=$current_index"
            local safe_title
            safe_title=$(echo "$(clean_title "$(cat "$CURRENT_SONG_FILE")")" | tr -s '[:space:]' '_')
            local cache_file="$CACHE_DIR/$safe_title.lrc"
            save_lyrics_to_file "$current_index" "$cache_file"
            local lyric
            lyric=$(get_current_lyric "$(get_position)" "$cache_file")
            echo "$lyric"
            return 0
            ;;
        *)
            log "Invalid click type: $click_type"
            echo "$(get_selected_title)"
            return 1
    esac
    echo "$new_index" > "$SELECTED_INDEX_FILE"
    local selected_title
    selected_title=$(get_selected_title)
    log "Options cycled: new_index=$new_index, selected_title=$selected_title"
    echo "$selected_title"
}

# Get current lyric line
get_current_lyric() {
    local pos_sec="$1"
    local cache_file="$2"
    local selected_index
    selected_index=$(cat "$SELECTED_INDEX_FILE" 2>/dev/null || echo "0")

    # Log cache file contents for debugging
    if [ -f "$cache_file" ]; then
        log "Cache file contents ($cache_file):"
        log "$(cat "$cache_file")"
    else
        log "Cache file not found: $cache_file"
    fi

    # Try reading from cache file first
    if [ -f "$cache_file" ]; then
        log "Reading lyrics from cache: $cache_file"
        local line
        line=$(awk -v pos="$pos_sec" '
            BEGIN { last_sec = -1; line = "♫" }
            /^\[[0-9]{1,2}:[0-9]{2}\.[0-9]{2}\]/ {
                timestamp = gensub(/^\[([0-9]{1,2}):([0-9]{2})\.([0-9]{2})\].*/, "\\1 \\2 \\3", "g", $1)
                split(timestamp, parts, " ")
                minutes = parts[1] + 0
                seconds = parts[2] + 0
                hundredths = parts[3] + 0
                sec = minutes * 60 + seconds + hundredths / 100
                printf("DEBUG: Processing timestamp %s, sec=%.2f, pos=%.2f, last_sec=%.2f\n", $1, sec, pos, last_sec) > "/dev/stderr"
                if (sec <= pos && sec > last_sec) {
                    last_sec = sec
                    sub(/^\[[0-9]{1,2}:[0-9]{2}\.[0-9]{2}\]([[:space:]]*)?/, "")
                    line = $0 ? $0 : "No lyric at this time"
                    printf("DEBUG: Updated line to \"%s\" at sec=%.2f\n", line, sec) > "/dev/stderr"
                }
            }
            END { print line }
        ' "$cache_file" 2>>"$ERROR_LOG")
        log "Lyric line at position $pos_sec from cache: $line"
        if [ -n "$line" ] && [ "$line" != "No lyric at this time" ]; then
            echo "$line"
            return
        fi
    fi

    # Fallback to API response
    local synced_lyrics
    synced_lyrics=$(jq -r ".[$selected_index].syncedLyrics" "$API_RESPONSE_LOG" 2>/dev/null)
    log "Synced lyrics for index=$selected_index: $synced_lyrics"
    if [ "$synced_lyrics" = "null" ] || [ -z "$synced_lyrics" ]; then
        local plain_lyrics
        plain_lyrics=$(jq -r ".[$selected_index].plainLyrics" "$API_RESPONSE_LOG" 2>/dev/null)
        log "Falling back to plain lyrics: $plain_lyrics"
        if [ "$plain_lyrics" != "null" ] && [ -n "$plain_lyrics" ]; then
            echo "$plain_lyrics" | head -n 1
        else
            echo "No lyrics available"
        fi
        return
    fi
    local line
    line=$(echo "$synced_lyrics" | awk -v pos="$pos_sec" '
        BEGIN { last_sec = -1; line = "No lyric at this time" }
        /^\[[0-9]{1,2}:[0-9]{2}\.[0-9]{2}\]/ {
            timestamp = gensub(/^\[([0-9]{1,2}):([0-9]{2})\.([0-9]{2})\].*/, "\\1 \\2 \\3", "g", $1)
            split(timestamp, parts, " ")
            minutes = parts[1] + 0
            seconds = parts[2] + 0
            hundredths = parts[3] + 0
            sec = minutes * 60 + seconds + hundredths / 100
            printf("DEBUG: Processing timestamp %s, sec=%.2f, pos=%.2f, last_sec=%.2f\n", $1, sec, pos, last_sec) > "/dev/stderr"
            if (sec <= pos && sec > last_sec) {
                last_sec = sec
                sub(/^\[[0-9]{1,2}:[0-9]{2}\.[0-9]{2}\]([[:space:]]*)?/, "")
                line = $0 ? $0 : "No lyric at this time"
                printf("DEBUG: Updated line to \"%s\" at sec=%.2f\n", line, sec) > "/dev/stderr"
            }
        }
        END { print line }
    ' 2>>"$ERROR_LOG")
    log "Lyric line at position $pos_sec: $line"
    echo "$line"
}

# Main logic
main() {
    local player_status
    player_status=$(playerctl status 2>/dev/null || echo "Stopped")
    if [ "$player_status" != "Playing" ]; then
        echo "No song playing"
        exit 0
    fi

    local raw_title
    raw_title=$(playerctl metadata title 2>/dev/null)
    [ -z "$raw_title" ] && { echo "No song title available"; exit 0; }

    local clean_title
    clean_title=$(clean_title "$raw_title")
    [ -z "$clean_title" ] && { echo "Invalid song title"; exit 0; }

    local current_song
    [ -f "$CURRENT_SONG_FILE" ] && current_song=$(cat "$CURRENT_SONG_FILE") || current_song=""

    if [ "$current_song" != "$raw_title" ]; then
        log "Song changed to: $raw_title"
        echo "$raw_title" > "$CURRENT_SONG_FILE"
        rm -f "$SELECTED_INDEX_FILE" "$OPTIONS_FILE" "$API_RESPONSE_LOG" "$SELECTION_CONFIRMED_FILE"
        echo "0" > "$SELECTED_INDEX_FILE"
    fi

    local pos_sec
    pos_sec=$(get_position)
    local safe_title
    safe_title=$(echo "$clean_title" | tr -s '[:space:]' '_')
    local cache_file="$CACHE_DIR/$safe_title.lrc"

    local last_fetch
    last_fetch=$(cat "$LAST_FETCH_FILE" 2>/dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    if [ ! -f "$API_RESPONSE_LOG" ] || [ $((current_time - last_fetch)) -gt 300 ]; then
        fetch_lyrics "$clean_title" "$cache_file"
    fi

    local options
    options=$(parse_options)
    local options_count
    options_count=$(echo "$options" | wc -l)
    log "Options count: $options_count"

    if [ "$options_count" -eq 0 ]; then
        echo "No lyrics found"
        exit 0
    elif [ "$options_count" -eq 1 ]; then
        echo "0" > "$SELECTED_INDEX_FILE"
        touch "$SELECTION_CONFIRMED_FILE"
        if [ ! -f "$cache_file" ]; then
            save_lyrics_to_file "0" "$cache_file"
        fi
    fi

    local click_type="$1"
    if [ -n "$click_type" ]; then
        handle_click "$click_type" "$options_count"
        exit 0
    fi

    if [ "$options_count" -gt 1 ] && [ ! -f "$SELECTION_CONFIRMED_FILE" ]; then
        local selected_index
        selected_index=$(cat "$SELECTED_INDEX_FILE" 2>/dev/null || echo "0")
        local last_modified
        last_modified=$(stat -c %Y "$SELECTED_INDEX_FILE" 2>/dev/null || echo "0")
        if [ $((current_time - last_modified)) -gt $SELECTION_TIMEOUT ]; then
            log "Selection timed out, auto-confirming index $selected_index"
            touch "$SELECTION_CONFIRMED_FILE"
            save_lyrics_to_file "$selected_index" "$cache_file"
        fi
        echo "$(get_selected_title)"
        exit 0
    fi

    local lyric
    lyric=$(get_current_lyric "$pos_sec" "$cache_file")
    log "Output to Waybar: $lyric"
    echo "$lyric"
}

main "$@"
