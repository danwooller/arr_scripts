#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# --- Configuration ---
TARGET_DIR="${1:-/mnt/media/Movies}"

# Prevent '*' literal if no matches found
shopt -s nullglob

echo "Scanning directories in: $TARGET_DIR"

for dir in "$TARGET_DIR"/*/ ; do
    [[ -d "$dir" ]] || continue

    # Strip trailing slash and get folder name
    dir_full_path="${dir%/}"
    dir_name=$(basename "$dir_full_path")
    parent_dir=$(dirname "$dir_full_path")

    # Extract year from folder name: "Movie Title (YYYY)"
    if [[ "$dir_name" =~ \(([0-9]{4})\) ]]; then
        folder_year="${BASH_REMATCH[1]}"
        movie_title="${dir_name% (*}"
        
        echo "------------------------------------------------"
        echo "Checking: $movie_title"

        check_and_fix() {
            local base_url=$1
            local api_key=$2
            local label=$3

            # Query Radarr API
            response=$(curl -s -G --data-urlencode "term=$movie_title" \
                "$base_url/movie/lookup" \
                -H "X-Api-Key: $api_key")

            # Extract year from first match where title matches exactly
            radarr_year=$(echo "$response" | jq -r ".[] | select(.title==\"$movie_title\") | .year" | head -n 1)

            if [[ -z "$radarr_year" || "$radarr_year" == "null" ]]; then
                echo "[$label] Result: Not found in database."
                return 1
            elif [[ "$radarr_year" == "$folder_year" ]]; then
                echo "[$label] Result: MATCH ($radarr_year)"
                return 0
            else
                echo "[$label] Result: MISMATCH! (Radarr says $radarr_year)"
                
                new_name="$movie_title ($radarr_year)"
                new_path="$parent_dir/$new_name"

                if [[ -d "$new_path" ]]; then
                    echo "[$label] ERROR: Cannot rename, '$new_name' already exists."
                else
                    echo "[$label] ACTION: Renaming folder to '$new_name'..."
                    mv "$dir_full_path" "$new_path"
                    
                    # 1. Update global path variable for the next check (4K)
                    dir_full_path="$new_path" 

                    # 2. Trigger Radarr Rescan for this specific movie
                    # We fetch the internal Radarr ID using the NEW path
                    local r_id=$(curl -s -H "X-Api-Key: $api_key" "$base_url/movie" | \
                                jq -r --arg p "$new_path" '.[] | select(.path == $p or .path == ($p + "/")) | .id')
                    
                    if [[ -n "$r_id" && "$r_id" != "null" ]]; then
                        echo "[$label] Triggering Radarr Rescan (ID: $r_id)..."
                        curl -s -X POST "$base_url/command" -H "X-Api-Key: $api_key" \
                             -H "Content-Type: application/json" \
                             -d "{\"name\": \"RescanMovie\", \"movieId\": $r_id}" > /dev/null
                    fi

                    # 3. Resolve Seerr Issue
                    # Since the year is now fixed, any open "Issue" in Overseerr/Prowlarr can be closed.
                    echo "[$label] Syncing with Seerr..."
                    resolve_seerr_issue "$new_path"
                fi
                return 2
            fi
        }

        # Check Standard first
        check_and_fix "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
        
        # Check 4K instance (uses updated dir_full_path if Standard renamed it)
        check_and_fix "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"

    fi
done

echo "------------------------------------------------"
echo "Scan complete."
