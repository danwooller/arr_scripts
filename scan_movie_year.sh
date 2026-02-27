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

    if [[ "$dir_name" =~ \(([0-9]{4})\) ]]; then
        folder_year="${BASH_REMATCH[1]}"
        movie_title="${dir_name% (*}"
        
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Checking filesystem entry: $movie_title"

        process_instance() {
            local base_url=$1
            local api_key=$2
            local label=$3
            
            # 1. Fetch ALL movies matching the title
            local response=$(curl -s -H "X-Api-Key: $api_key" "$base_url/movie")

            # 2. Refined JQ: Match Title AND existing Folder Year to find the SPECIFIC record
            # This prevents remakes (like 'The Courier') from doubling up.
            local movie_json=$(echo "$response" | jq -c --arg t "$movie_title" --arg y "$folder_year" \
                '.[] | select(.title == $t and (.year|tostring) == $y)')

            if [[ -z "$movie_json" || "$movie_json" == "null" ]]; then
                [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] No exact Title+Year match for '$movie_title ($folder_year)'."
                return 1
            fi

            local radarr_id=$(echo "$movie_json" | jq -r '.id')
            local radarr_year=$(echo "$movie_json" | jq -r '.year')
            
            # Since we matched by year, they will always match here. 
            # However, we still check the PATH to see if the database needs an update.
            local db_path=$(echo "$movie_json" | jq -r '.path')

            if [[ "$db_path" == "$current_full_path" ]]; then
                [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] Path and Year already correct in DB."
                return 0
            else
                # If the folder year is correct but the path in Radarr is wrong 
                # (e.g., folder was moved/renamed manually before), we sync it.
                log "✅ [$label] Syncing Radarr path for: $movie_title ($radarr_year)"
                
                local updated_json=$(echo "$movie_json" | jq -c --arg p "$current_full_path" '.path = $p')
                
                curl -s -X PUT "$base_url/movie" \
                     -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" \
                     -d "$updated_json" > /dev/null

                curl -s -X POST "$base_url/command" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" \
                     -d "{\"name\": \"RescanMovie\", \"movieId\": $radarr_id}" > /dev/null

                return 2
            fi
        }

        # --- Decision Tree ---
        any_change=0
        if [[ "$current_full_path" == *"4kMovies"* ]]; then
            process_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"
            [[ $? -eq 2 ]] && any_change=1
        else
            process_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
            [[ $? -eq 2 ]] && any_change=1
        fi

        if [[ $any_change -eq 1 ]]; then
             resolve_seerr_issue "$current_full_path"
        fi
    fi
done

log "🏁 Scan complete."
