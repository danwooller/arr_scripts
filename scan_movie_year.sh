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
            
            # 1. Fetch ALL movies matching the title from your library
            local response=$(curl -s -H "X-Api-Key: $api_key" "$base_url/movie")

            # 2. Find the correct movie record. 
            # We look for a title match. If multiple (remakes), we pick the one 
            # that currently matches the filesystem path OR the title.
            local movie_json=$(echo "$response" | jq -c --arg t "$movie_title" --arg p "$current_full_path" \
                '.[] | select(.title == $t and (.path == $p or .path == ($p + "/")))')

            # Fallback: If path doesn't match (because it's already broken), 
            # just get the first movie matching the title.
            if [[ -z "$movie_json" || "$movie_json" == "null" ]]; then
                movie_json=$(echo "$response" | jq -c --arg t "$movie_title" '.[] | select(.title == $t) | first')
            fi

            if [[ -z "$movie_json" || "$movie_json" == "null" ]]; then
                [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] Movie '$movie_title' not found in database."
                return 1
            fi

            local radarr_id=$(echo "$movie_json" | jq -r '.id')
            local radarr_year=$(echo "$movie_json" | jq -r '.year')
            local db_path=$(echo "$movie_json" | jq -r '.path')

            # 3. Check for Year Mismatch
            if [[ "$radarr_year" != "$folder_year" ]]; then
                local new_name="$movie_title ($radarr_year)"
                local new_path="$parent_dir/$new_name"

                log "⚠️ [$label] Year Mismatch: '$dir_name' should be '$new_name'. Fixing..."
                
                # Rename the actual folder
                if [[ -d "$new_path" ]]; then
                    log "❌ [$label] Error: Target '$new_name' already exists. Skipping rename."
                else
                    mv "$current_full_path" "$new_path"
                    current_full_path="$new_path"
                fi

                # Update Radarr's Path
                local updated_json=$(echo "$movie_json" | jq -c --arg p "$current_full_path" '.path = $p')
                curl -s -X PUT "$base_url/movie" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" -d "$updated_json" > /dev/null

                # Trigger Rescan
                curl -s -X POST "$base_url/command" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" -d "{\"name\": \"RescanMovie\", \"movieId\": $radarr_id}" > /dev/null
                
                return 2
            fi

            # 4. If Year matches but Path is wrong in DB, sync path only
            if [[ "$db_path" != "$current_full_path" ]]; then
                log "✅ [$label] Path Sync: Updating DB path for $movie_title ($radarr_year)"
                local updated_json=$(echo "$movie_json" | jq -c --arg p "$current_full_path" '.path = $p')
                curl -s -X PUT "$base_url/movie" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" -d "$updated_json" > /dev/null
                curl -s -X POST "$base_url/command" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" -d "{\"name\": \"RescanMovie\", \"movieId\": $radarr_id}" > /dev/null
                return 2
            fi

            return 0
        }

        # --- Instance Routing ---
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
