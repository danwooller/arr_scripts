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

    # Initial path setup
    current_full_path="${dir%/}"
    dir_name=$(basename "$current_full_path")
    parent_dir=$(dirname "$current_full_path")

    # Extract year from folder name: "Movie Title (YYYY)"
    if [[ "$dir_name" =~ \(([0-9]{4})\) ]]; then
        folder_year="${BASH_REMATCH[1]}"
        movie_title="${dir_name% (*}"
        
        echo "------------------------------------------------"
        echo "Checking: $movie_title"

        # Function to process an instance
        # Returns 0 if year matches, 2 if renamed, 1 if not found/error
        process_instance() {
            local base_url=$1
            local api_key=$2
            local label=$3
            
            # 1. Fetch data from Radarr
            local response=$(curl -s -G --data-urlencode "term=$movie_title" \
                "$base_url/movie/lookup" \
                -H "X-Api-Key: $api_key")

            local radarr_year=$(echo "$response" | jq -r ".[] | select(.title==\"$movie_title\") | .year" | head -n 1)

            if [[ -z "$radarr_year" || "$radarr_year" == "null" ]]; then
                echo "[$label] Result: Movie not found in this instance."
                return 1
            fi

            # 2. Check for mismatch
            # We re-extract the folder year because it might have changed in the previous loop
            local current_folder_name=$(basename "$current_full_path")
            [[ "$current_folder_name" =~ \(([0-9]{4})\) ]]
            local current_folder_year="${BASH_REMATCH[1]}"

            if [[ "$radarr_year" == "$current_folder_year" ]]; then
                echo "[$label] Result: MATCH ($radarr_year)"
                return 0
            else
                echo "[$label] Result: MISMATCH! (Radarr says $radarr_year, Folder has $current_folder_year)"
                
                local new_name="$movie_title ($radarr_year)"
                local new_path="$parent_dir/$new_name"

                if [[ -d "$new_path" ]]; then
                    echo "[$label] NOTICE: Target '$new_name' already exists. Updating path reference..."
                    current_full_path="$new_path"
                    return 2
                else
                    echo "[$label] ACTION: Renaming folder to '$new_name'..."
                    mv "$current_full_path" "$new_path"
                    current_full_path="$new_path"
                    
                    # Trigger Radarr Rescan so Seerr lookup works later
                    local r_id=$(echo "$response" | jq -r ".[] | select(.title==\"$movie_title\") | .id")
                    if [[ -n "$r_id" && "$r_id" != "null" ]]; then
                        curl -s -X POST "$base_url/command" -H "X-Api-Key: $api_key" \
                             -H "Content-Type: application/json" \
                             -d "{\"name\": \"RescanMovie\", \"movieId\": $r_id}" > /dev/null
                    fi
                    return 2
                fi
            fi
        }

        # Check Standard
        process_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
        std_status=$?

        # Check 4K (Now uses the updated current_full_path)
        process_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"
        fourk_status=$?

        # Final Sync with Seerr if any change occurred
        if [[ $std_status -eq 2 || $fourk_status -eq 2 ]]; then
             echo "[System] Syncing with Seerr for updated path..."
             # Optional: Add a small sleep to let Radarr database update its path record
             sleep 1
             resolve_seerr_issue "$current_full_path"
        fi
    fi
done

echo "------------------------------------------------"
echo "Scan complete."
