#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# --- Configuration ---
TARGET_DIR="${1:-/mnt/media/Movies}"
shopt -s nullglob

echo "Scanning directories in: $TARGET_DIR"

for dir in "$TARGET_DIR"/*/ ; do
    [[ -d "$dir" ]] || continue

    current_full_path="${dir%/}"
    dir_name=$(basename "$current_full_path")
    parent_dir=$(dirname "$current_full_path")

    if [[ "$dir_name" =~ \(([0-9]{4})\) ]]; then
        folder_year="${BASH_REMATCH[1]}"
        movie_title="${dir_name% (*}"
        
        echo "------------------------------------------------"
        echo "Checking: $movie_title"

        process_instance() {
            local base_url=$1
            local api_key=$2
            local label=$3
            
            # 1. Fetch current database record for this movie
            # We search specifically for the title to get the internal ID and TMDB info
            local movie_json=$(curl -s -H "X-Api-Key: $api_key" "$base_url/movie" | \
                jq -c --arg t "$movie_title" '.[] | select(.title == $t)')

            if [[ -z "$movie_json" ]]; then
                echo "[$label] Result: Movie not found in database."
                return 1
            fi

            local radarr_id=$(echo "$movie_json" | jq -r '.id')
            local radarr_year=$(echo "$movie_json" | jq -r '.year')
            local current_folder_name=$(basename "$current_full_path")
            [[ "$current_folder_name" =~ \(([0-9]{4})\) ]]
            local current_folder_year="${BASH_REMATCH[1]}"

            if [[ "$radarr_year" == "$current_folder_year" ]]; then
                echo "[$label] Result: MATCH ($radarr_year)"
                return 0
            else
                echo "[$label] Result: MISMATCH! (Radarr: $radarr_year vs Folder: $current_folder_year)"
                
                local new_name="$movie_title ($radarr_year)"
                local new_path="$parent_dir/$new_name"

                if [[ -d "$new_path" && "$current_full_path" != "$new_path" ]]; then
                    echo "[$label] NOTICE: Target path exists. Syncing database path only..."
                else
                    echo "[$label] ACTION: Renaming filesystem folder..."
                    mv "$current_full_path" "$new_path"
                fi

                # --- CRITICAL: Update Radarr's Internal Path ---
                echo "[$label] Updating Radarr database path to: $new_path"
                
                # Update the path in the JSON and PUT it back to the API
                local updated_json=$(echo "$movie_json" | jq -c --arg p "$new_path" '.path = $p')
                
                curl -s -X PUT "$base_url/movie" \
                     -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" \
                     -d "$updated_json" > /dev/null

                # Now trigger Rescan so it sees the files at the new path
                curl -s -X POST "$base_url/command" -H "X-Api-Key: $api_key" \
                     -H "Content-Type: application/json" \
                     -d "{\"name\": \"RescanMovie\", \"movieId\": $radarr_id}" > /dev/null

                current_full_path="$new_path"
                return 2
            fi
        }

        # Run for Standard
        process_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
        std_status=$?

        # Run for 4K (Uses updated path from Standard)
        process_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"
        fourk_status=$?

        # Final Sync with Seerr
        if [[ $std_status -eq 2 || $fourk_status -eq 2 ]]; then
             echo "[System] Resolving Seerr issues for: $current_full_path"
             resolve_seerr_issue "$current_full_path"
        fi
    fi
done

echo "------------------------------------------------"
echo "Scan complete."
