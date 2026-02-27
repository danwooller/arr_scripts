#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# --- Configuration ---
TARGET_DIR="${1:-/mnt/media/Movies}"
shopt -s nullglob

log "🚀 Starting Movie Year Scan in: $TARGET_DIR"

for dir in "$TARGET_DIR"/*/ ; do
    [[ -d "$dir" ]] || continue

    current_full_path="${dir%/}"
    dir_name=$(basename "$current_full_path")
    parent_dir=$(dirname "$current_full_path")

    # Extract year from folder name: "Movie Title (YYYY)"
    if [[ "$dir_name" =~ \(([0-9]{4})\) ]]; then
        folder_year="${BASH_REMATCH[1]}"
        movie_title="${dir_name% (*}"
        
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Checking filesystem entry: $movie_title"

        process_instance() {
            local base_url=$1
            local api_key=$2
            local label=$3
            
            # Fetch movies from Radarr
            local response=$(curl -s -H "X-Api-Key: $api_key" "$base_url/movie")

            # Match by Title AND Year to avoid the "Remake/Duplicate Title" bug
            local movie_json=$(echo "$response" | jq -c --arg t "$movie_title" --arg y "$folder_year" \
                '.[] | select(.title == $t and (.year|tostring) == $y)')

            if [[ -z "$movie_json" || "$movie_json" == "null" ]]; then
                [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] No Title+Year match found in DB for $movie_title ($folder_year)."
                return 1
            fi

            local radarr_id=$(echo "$movie_json" | jq -r '.id')
            local db_path=$(echo "$movie_json" | jq -r '.path')

            # Check if Radarr's path record is out of sync with current filesystem path
            if [[ "$db_path" == "$current_full_path" ]]; then
                [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] Path already correct in DB."
                return 0
            else
                log "✅ [$label] Syncing Radarr path for: $movie_title ($folder_year)"
                
                # Update the path in Radarr's database
                local updated_json=$(echo "$movie_json" | jq -c --arg p "$current_full_path" '.path = $p')
                
                curl -s -X PUT "$base_url/movie" \
                     -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" \
                     -d "$updated_json" > /dev/null

                # Trigger Rescan to refresh metadata/file status
                curl -s -X POST "$base_url/command" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" \
                     -d "{\"name\": \"RescanMovie\", \"movieId\": $radarr_id}" > /dev/null

                return 2
            fi
        }

        # Route to correct instance
        any_change=0
        if [[ "$current_full_path" == *"4kMovies"* ]]; then
            process_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"
            [[ $? -eq 2 ]] && any_change=1
        else
            process_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
            [[ $? -eq 2 ]] && any_change=1
        fi

        # Clear any Seerr issues if we synced the path
        if [[ $any_change -eq 1 ]]; then
             resolve_seerr_issue "$current_full_path"
        fi
    fi
done

log "🏁 Scan complete."
