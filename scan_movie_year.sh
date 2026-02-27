#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# --- Configuration ---
TARGET_DIR="${1:-/mnt/media/Movies}"
shopt -s nullglob

log_start "$TARGET_DIR"
#log "🚀 Starting Movie Year Scan in: $TARGET_DIR"

for dir in "$TARGET_DIR"/*/ ; do
    [[ -d "$dir" ]] || continue

    current_full_path="${dir%/}"
    dir_name=$(basename "$current_full_path")
    parent_dir=$(dirname "$current_full_path")

    if [[ "$dir_name" =~ \(([0-9]{4})\) ]]; then
        folder_year="${BASH_REMATCH[1]}"
        movie_title="${dir_name% (*}"
        
        # Reset tracking variables for this specific folder
        target_base=""
        target_key=""
        radarr_id=""
        any_change=0

        process_instance() {
            local base_url=$1
            local api_key=$2
            local label=$3
            
            local response=$(curl -s -H "X-Api-Key: $api_key" "$base_url/movie")
            local movie_json=$(echo "$response" | jq -c --arg t "$movie_title" --arg p "$current_full_path" \
                '.[] | select(.title == $t and (.path == $p or .path == ($p + "/")))')

            if [[ -z "$movie_json" || "$movie_json" == "null" ]]; then
                movie_json=$(echo "$response" | jq -c --arg t "$movie_title" '.[] | select(.title == $t) | first')
            fi

            if [[ -z "$movie_json" || "$movie_json" == "null" ]]; then return 1; fi

            local current_radarr_id=$(echo "$movie_json" | jq -r '.id')
            local radarr_year=$(echo "$movie_json" | jq -r '.year')
            local db_path=$(echo "$movie_json" | jq -r '.path')

            if [[ "$radarr_year" != "$folder_year" || "$db_path" != "$current_full_path" ]]; then
                local new_path="$current_full_path"
                if [[ "$radarr_year" != "$folder_year" ]]; then
                    local new_name="$movie_title ($radarr_year)"
                    new_path="$parent_dir/$new_name"
                    log "⚠️ [$label] Year Mismatch: '$dir_name' -> '$new_name'."
                    [[ ! -d "$new_path" ]] && mv "$current_full_path" "$new_path"
                else
                    log "✅ [$label] Path Sync only for: $movie_title ($radarr_year)"
                fi

                # Update DB Path
                local updated_json=$(echo "$movie_json" | jq -c --arg p "$new_path" '.path = $p')
                curl -s -X PUT "$base_url/movie" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" -d "$updated_json" > /dev/null

                # Export data to parent scope
                target_base="$base_url"
                target_key="$api_key"
                radarr_id="$current_radarr_id"
                current_full_path="$new_path"
                return 2
            fi
            return 0
        }

        # --- Instance Routing ---
        if [[ "$current_full_path" == *"4kMovies"* ]]; then
            process_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"
            [[ $? -eq 2 ]] && any_change=1
        else
            process_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
            [[ $? -eq 2 ]] && any_change=1
        fi

        # --- The Final Sync & Targeted Refresh ---
        if [[ $any_change -eq 1 ]]; then
             # 1. Resolve Seerr issue
             resolve_seerr_issue "$current_full_path"

             # 2. Targeted Refresh (Using singular movieId to prevent full library scan)
             if [[ -n "$radarr_id" && "$radarr_id" != "null" ]]; then
                 [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Triggering targeted rescan for Movie ID: $radarr_id"
                 curl -s -X POST "$target_base/command" \
                    -H "X-Api-Key: $target_key" -H "Content-Type: application/json" \
                    -d "{\"name\": \"RescanMovie\", \"movieId\": $radarr_id}" > /dev/null
             fi
        fi
    fi
done

log "🏁 Scan complete."
