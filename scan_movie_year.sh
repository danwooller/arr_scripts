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

        check_instance() {
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
                
                # Construct new name
                new_name="$movie_title ($radarr_year)"
                new_path="$parent_dir/$new_name"

                if [[ -d "$new_path" ]]; then
                    echo "[$label] ERROR: Cannot rename, '$new_name' already exists."
                else
                    echo "[$label] ACTION: Renaming folder to '$new_name'..."
                    mv "$dir_full_path" "$new_path"
                    # Update variable so the next instance check doesn't fail or try to rename again
                    dir_full_path="$new_path" 
                fi
                return 2
            fi
        }

        # Check Standard first, then 4K
        check_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
        # If Standard already renamed it, $dir_full_path is updated for the 4K check
        check_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"

    fi
done

echo "------------------------------------------------"
echo "Scan complete."
