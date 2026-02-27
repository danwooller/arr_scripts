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

        # --- Instance Processing Function ---
        process_instance() {
            local base_url=$1
            local api_key=$2
            local label=$3
            
            # Fetch current database record
            local movie_json=$(curl -s -H "X-Api-Key: $api_key" "$base_url/movie" | \
                jq -c --arg t "$movie_title" '.[] | select(.title == $t)')

            if [[ -z "$movie_json" ]]; then
                [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] Movie not found in database."
                return 1
            fi

            local radarr_id=$(echo "$movie_json" | jq -r '.id')
            local radarr_year=$(echo "$movie_json" | jq -r '.year')
            
            if [[ "$radarr_year" == "$folder_year" ]]; then
                [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] Year match confirmed ($radarr_year)."
                return 0
            else
                local new_name="$movie_title ($radarr_year)"
                local new_path="$parent_dir/$new_name"

                if [[ -d "$new_path" && "$current_full_path" != "$new_path" ]]; then
                    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] Target path already exists. Syncing database path only."
                else
                    log "✅ [$label] Renaming: '$dir_name' -> '$new_name'"
                    mv "$current_full_path" "$new_path"
                fi

                # Update Radarr's Internal Path via PUT
                [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ [$label] Updating Radarr DB path for ID $radarr_id"
                local updated_json=$(echo "$movie_json" | jq -c --arg p "$new_path" '.path = $p')
                
                curl -s -X PUT "$base_url/movie" \
                     -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" \
                     -d "$updated_json" > /dev/null

                # Trigger Rescan
                curl -s -X POST "$base_url/command" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" \
                     -d "{\"name\": \"RescanMovie\", \"movieId\": $radarr_id}" > /dev/null

                current_full_path="$new_path"
                return 2
            fi
        }

        # --- Decision Tree ---
        any_change=0

        if [[ "$current_full_path" == *"4kMovies"* ]]; then
            # Target 4K Radarr
            process_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"
            [[ $? -eq 2 ]] && any_change=1
        else
            # Target Standard Radarr
            process_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
            [[ $? -eq 2 ]] && any_change=1
        fi

        # Sync with Seerr if a rename happened
        if [[ $any_change -eq 1 ]]; then
             resolve_seerr_issue "$current_full_path"
        fi
    fi
done

log "🏁 Scan complete."
