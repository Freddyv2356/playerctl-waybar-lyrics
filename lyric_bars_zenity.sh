#!/usr/bin/env bash
# Crappily coded by Freddyv2356 / KuronSub
# Configuration
CACHE_DIR="/home/$USER/Documents/lrclib_lyrics" # Your directory for storing info (You can change to whatever you want)
mkdir -p "$CACHE_DIR" # Make directory if it doesn't exist.
OFFSET=0.85 # Early offset for the script as the default execution interval is 1 sec.
SELECTED_INDEX_FILE="$CACHE_DIR/.selected_index" # Store your selection to get the lyric file.
OPTIONS_FILE="$CACHE_DIR/.options" # Setting file directory
ERROR_LOG="$CACHE_DIR/error.log" # Logging/Debugging directory
API_RESPONSE_LOG="$CACHE_DIR/api_response.json" # API Stuff with LRCLIB
CURRENT_SONG_FILE="$CACHE_DIR/current_song.txt" # Getting the title for the current song playing on your playerctl.
SELECTION_TIMEOUT=15 #Time it took before the script automatically choose (Usually the first result that it show will be the chosen one.)
LAST_FETCH_FILE="$CACHE_DIR/.last_fetch" #More caching out
SELECTION_CONFIRMED_FILE="$CACHE_DIR/.selection_confirmed" # Confirm your selection
MAX_CACHE_AGE=inf  # Maximum age of cache file in hours, set to "inf" to never re-download
ERROR_LOG_SIZE=20  # Maximum size of error.log in MB
ERROR_LOG_SIZE_BYTES=$((ERROR_LOG_SIZE * 1000000))  # Convert MB to bytes
STATE_FILE="$CACHE_DIR/.script_state"  # File to store enabled/disabled state
ENABLED_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "enabled")  # Load state, default to enabled

# Ensure UTF-8 encoding
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$ERROR_LOG"
}

# Check and manage error.log size
check_log_size() {
    if [ -f "$ERROR_LOG" ]; then
        local log_size
        log_size=$(stat -c %s "$ERROR_LOG" 2>/dev/null || echo 0)
        if [ "$log_size" -gt "$ERROR_LOG_SIZE_BYTES" ]; then
            rm -f "$ERROR_LOG"
            touch "$ERROR_LOG"
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error log exceeded ${ERROR_LOG_SIZE}MB, deleted and recreated" >> "$ERROR_LOG"
        fi
    else
        touch "$ERROR_LOG"
    fi
}

# Clean title function
clean_title() {
    local title="$1"
    title=$(echo "$title" | sed -E 's/\([^)]*\)//g; s/\[[^]]*\]//g; s/【[^】]*】//g; s/ (MV|VIDEO|OFFICIAL|feat\.?|ft\.?|MUSIC)//ig; s/[[:space:]]*$//')
    echo "$title"
}

# Parse title into track and artist
parse_title() {
    local title="$1"
    local track artist
    if [[ "$title" =~ ^(.*)[[:space:]]*[/-][[:space:]]*(.*)$ ]]; then
        track="${BASH_REMATCH[1]}"
        artist="${BASH_REMATCH[2]}"
        track=$(echo "$track" | sed 's/[[:space:]]*$//')
        artist=$(echo "$artist" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        track="$title"
        artist=""
    fi
    echo "$track" "$artist"
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

# Fetch lyrics with priority for synced lyrics
fetch_lyrics() {
    local title="$1"
    local cache_file="$2"
    local current_time
    current_time=$(date +%s)
    local temp_response="$CACHE_DIR/temp_response.json"

    # Check if cache file exists and is recent enough
    if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
        if [ "$MAX_CACHE_AGE" = "inf" ]; then
            log "Cache file exists and MAX_CACHE_AGE is 'inf', skipping fetch: $cache_file"
            return 0
        fi
        local file_age
        file_age=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        local age_hours=$(( (current_time - file_age) / 3600 ))
        if [ "$age_hours" -lt "$MAX_CACHE_AGE" ]; then
            log "Cache file is recent (age: $age_hours hours < $MAX_CACHE_AGE hours), skipping fetch: $cache_file"
            return 0
        else
            log "Cache file is too old (age: $age_hours hours >= $MAX_CACHE_AGE hours), fetching new lyrics"
        fi
    fi

    rm -f "$temp_response" "$API_RESPONSE_LOG"
    echo "[]" > "$API_RESPONSE_LOG"

    # Split title by - and /
    local title_parts
    title_parts=$(echo "$title" | awk -F '[/-]' '{for(i=1;i<=NF;i++) if ($i !~ /^[[:space:]]*$/) print $i}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    log "Title parts for search: $title_parts"

    # Search full title
    local encoded_title
    encoded_title=$(printf '%s' "$title" | jq -Rr @uri)
    log "Searching full title: $title (encoded: $encoded_title)"
    local url="https://lrclib.net/api/search?q=$encoded_title"
    local response
    response=$(curl -s --fail "$url" -H "Accept: application/json" 2>>"$ERROR_LOG")
    if [ $? -eq 0 ]; then
        local has_synced_lyrics
        has_synced_lyrics=$(echo "$response" | jq -e '.[] | select(.syncedLyrics != null)' 2>>"$ERROR_LOG")
        if [ -n "$has_synced_lyrics" ]; then
            jq -n --argjson new "$response" '[$new[] | select(.syncedLyrics != null)]' > "$temp_response"
            jq -s '.[0] + .[1]' "$API_RESPONSE_LOG" "$temp_response" > "${API_RESPONSE_LOG}.tmp" && mv "${API_RESPONSE_LOG}.tmp" "$API_RESPONSE_LOG"
            log "Synced lyrics found for full title: $title"
        else
            log "No synced lyrics found for full title: $title"
        fi
    fi

    # Search each title part
    local part
    while IFS= read -r part; do
        if [ -n "$part" ]; then
            local encoded_part
            encoded_part=$(printf '%s' "$part" | jq -Rr @uri)
            url="https://lrclib.net/api/search?q=$encoded_part"
            log "Searching title part: $part (encoded: $encoded_part)"
            response=$(curl -s --fail "$url" -H "Accept: application/json" 2>>"$ERROR_LOG")
            if [ $? -eq 0 ]; then
                has_synced_lyrics=$(echo "$response" | jq -e '.[] | select(.syncedLyrics != null)' 2>>"$ERROR_LOG")
                if [ -n "$has_synced_lyrics" ]; then
                    jq -n --argjson new "$response" '[$new[] | select(.syncedLyrics != null)]' > "$temp_response"
                    jq -s '.[0] + .[1]' "$API_RESPONSE_LOG" "$temp_response" > "${API_RESPONSE_LOG}.tmp" && mv "${API_RESPONSE_LOG}.tmp" "$API_RESPONSE_LOG"
                    log "Synced lyrics found for part: $part"
                else
                    log "No synced lyrics found for part: $part"
                fi
            fi
        fi
    done <<< "$title_parts"

    # Track and artist search
    local track artist
    read -r track artist <<< "$(parse_title "$title")"
    if [ -n "$track" ] && [ -n "$artist" ]; then
        local encoded_track encoded_artist
        encoded_track=$(printf '%s' "$track" | jq -Rr @uri)
        encoded_artist=$(printf '%s' "$artist" | jq -Rr @uri)
        url="https://lrclib.net/api/search?track_name=$encoded_track&artist_name=$encoded_artist"
        log "Track and artist search: track=$track, artist=$artist"
        response=$(curl -s --fail "$url" -H "Accept: application/json" 2>>"$ERROR_LOG")
        if [ $? -eq 0 ]; then
            has_synced_lyrics=$(echo "$response" | jq -e '.[] | select(.syncedLyrics != null)' 2>>"$ERROR_LOG")
            if [ -n "$has_synced_lyrics" ]; then
                jq -n --argjson new "$response" '[$new[] | select(.syncedLyrics != null)]' > "$temp_response"
                jq -s '.[0] + .[1]' "$API_RESPONSE_LOG" "$temp_response" > "${API_RESPONSE_LOG}.tmp" && mv "${API_RESPONSE_LOG}.tmp" "$API_RESPONSE_LOG"
                log "Synced lyrics found for track: $track, artist: $artist"
            else
                log "No synced lyrics found for track: $track, artist: $artist"
            fi
        fi
    fi

    # Check if any synced lyrics were found
    local options_count
    options_count=$(jq -r '.[] | select(.syncedLyrics != null) | .name' "$API_RESPONSE_LOG" 2>>"$ERROR_LOG" | wc -l)
    if [ "$options_count" -eq 0 ]; then
        log "No synced lyrics found for title: $title or its parts"
        echo "No synced lyrics found" > "$cache_file"
        rm -f "$temp_response"
        return 1
    fi
    echo "$current_time" > "$LAST_FETCH_FILE"
    rm -f "$temp_response"
    return 0
}

# Parse options with synced lyrics
parse_options() {
    jq -r '.[] | select(.syncedLyrics != null) | "\(.name) [\(.duration)]"' "$API_RESPONSE_LOG" 2>>"$ERROR_LOG" | tee "$OPTIONS_FILE"
}

# Get selected lyric title
get_selected_title() {
    local selected_index
    selected_index=$(cat "$SELECTED_INDEX_FILE" 2>/dev/null || echo "0")
    awk -v idx="$selected_index" 'NR==idx+1' "$OPTIONS_FILE" 2>>"$ERROR_LOG" || echo "No title available"
}

# Save lyrics to file
save_lyrics_to_file() {
    local selected_index="$1"
    local cache_file="$2"
    local synced_lyrics
    synced_lyrics=$(jq -r ".[$selected_index].syncedLyrics" "$API_RESPONSE_LOG" 2>>"$ERROR_LOG")
    log "Checking synced lyrics for index=$selected_index: ${synced_lyrics:0:50}..."
    if [ "$synced_lyrics" != "null" ] && [ -n "$synced_lyrics" ]; then
        echo "$synced_lyrics" > "$cache_file"
        log "Saved synced lyrics to: $cache_file"
        return 0
    fi
    log "No synced lyrics available for index=$selected_index"
    echo "No synced lyrics found" > "$cache_file"
    return 1
}

# Handle click events
handle_click() {
    local click_type="$1"
    case "$click_type" in
        left|right)
            if [ "$ENABLED_STATE" = "enabled" ]; then
                echo "disabled" > "$STATE_FILE"
                log "Script disabled via $click_type click"
                echo "Stopped"
            else
                echo "enabled" > "$STATE_FILE"
                log "Script enabled via $click_type click"
                echo "Enabled"
            fi
            exit 0
            ;;
        *)
            log "Unknown click type: $click_type"
            return 1
            ;;
    esac
}

# Handle selection with Zenity
handle_selection() {
    local options_count="$1"
    local cache_file="$2"
    local current_index
    current_index=$(cat "$SELECTED_INDEX_FILE" 2>/dev/null || echo "0")

    if ! command -v zenity >/dev/null; then
        log "Zenity not found, defaulting to index=$current_index"
        echo "$current_index" > "$SELECTED_INDEX_FILE"
        touch "$SELECTION_CONFIRMED_FILE"
        save_lyrics_to_file "$current_index" "$cache_file"
        return 0
    fi

    # Use zenity for GUI selection
    local selected_option
    selected_option=$(cat "$OPTIONS_FILE" | zenity --list --title="Select Lyrics" --column="Song" --timeout="$SELECTION_TIMEOUT" --width=500 --height=400 2>>"$ERROR_LOG")
    if [ -z "$selected_option" ]; then
        log "Selection timed out after $SELECTION_TIMEOUT seconds, using default index=$current_index"
        selected_index="$current_index"
    else
        selected_index=$(grep -n "^$selected_option$" "$OPTIONS_FILE" | cut -d: -f1)
        selected_index=$((selected_index - 1))
        log "User selected index=$selected_index"
    fi

    echo "$selected_index" > "$SELECTED_INDEX_FILE"
    touch "$SELECTION_CONFIRMED_FILE"
    save_lyrics_to_file "$selected_index" "$cache_file"
    log "Selection confirmed: index=$selected_index"
    return 0
}

# Get current lyric line
get_current_lyric() {
    local pos_sec="$1"
    local cache_file="$2"
    local selected_index
    selected_index=$(cat "$SELECTED_INDEX_FILE" 2>/dev/null || echo "0")

    if [ -f "$cache_file" ]; then
        log "Cache file contents ($cache_file):"
        log "$(cat "$cache_file")"
    else
        log "Cache file not found: $cache_file"
    fi

    if [ -f "$cache_file" ]; then
        log "Reading lyrics from cache: $cache_file"
        local line
        line=$(awk -v pos="$pos_sec" '
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
        ' "$cache_file" 2>>"$ERROR_LOG")
        log "Lyric line at position $pos_sec from cache: $line"
        if [ -n "$line" ] && [ "$line" != "No lyric at this time" ]; then
            echo "$line"
            return
        fi
    fi

    local synced_lyrics
    synced_lyrics=$(jq -r ".[$selected_index].syncedLyrics" "$API_RESPONSE_LOG" 2>>"$ERROR_LOG")
    log "Checking synced lyrics for index=$selected_index: ${synced_lyrics:0:50}..."
    if [ "$synced_lyrics" = "null" ] || [ -z "$synced_lyrics" ]; then
        log "No synced lyrics available for index=$selected_index"
        echo "No synced lyrics found"
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
    # Check log file size before proceeding
    check_log_size

    # Handle click events
    local click_type="$1"
    if [ -n "$click_type" ]; then
        case "$click_type" in
            left|right)
                handle_click "$click_type"
                ;;
            *)
                log "Ignoring unknown click type: $click_type"
                ;;
        esac
    fi

    # Check if script is disabled
    if [ "$ENABLED_STATE" = "disabled" ]; then
        log "Script is disabled, exiting"
        echo "Stopped"
        exit 0
    fi

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
    safe_title=$(echo "$clean_title" | tr -s '[:space:]' '_' | tr '/' '_')
    local cache_file="$CACHE_DIR/$safe_title.lrc"

    local last_fetch
    last_fetch=$(cat "$LAST_FETCH_FILE" 2>/dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    if [ ! -f "$API_RESPONSE_LOG" ] || [ $((current_time - last_fetch)) -gt 300 ]; then
        fetch_lyrics "$clean_title" "$cache_file"
        echo "$current_time" > "$LAST_FETCH_FILE"
    fi

    local options
    options=$(parse_options)
    local options_count
    options_count=$(echo "$options" | wc -l)
    log "Options count: $options_count"

    if [ "$options_count" -eq 0 ]; then
        echo "No synced lyrics found"
        exit 0
    elif [ "$options_count" -eq 1 ]; then
        echo "0" > "$SELECTED_INDEX_FILE"
        touch "$SELECTION_CONFIRMED_FILE"
        if [ ! -f "$cache_file" ] || [ "$MAX_CACHE_AGE" != "inf" ]; then
            local file_age
            file_age=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
            local age_hours=$(( (current_time - file_age) / 3600 ))
            if [ ! -f "$cache_file" ] || [ "$age_hours" -ge "$MAX_CACHE_AGE" ]; then
                save_lyrics_to_file "0" "$cache_file"
            fi
        fi
    fi

    if [ "$options_count" -gt 1 ] && [ ! -f "$SELECTION_CONFIRMED_FILE" ]; then
        handle_selection "$options_count" "$cache_file"
        # After selection, display the selected title and exit to avoid premature lyric display
        echo "$(get_selected_title)"
        exit 0
    fi

    local lyric
    lyric=$(get_current_lyric "$pos_sec" "$cache_file")
    log "Output to Waybar: $lyric"
    echo "$lyric"
}

main "$@"
