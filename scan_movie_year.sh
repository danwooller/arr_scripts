#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# --- Configuration ---
TARGET_DIR="${1:-/mnt/media/Movies}"

# Prevent '*' literal if directory is empty or no matches found
shopt -s nullglob

echo "Scanning directories in: $TARGET_DIR"

# Iterate through each folder
for dir in "$TARGET_DIR"/*/ ; do
    # Ensure it's a directory
    [[ -d "$dir" ]] || continue

    # Strip trailing slash and get folder name
    dir_name=$(basename "$dir")

    # Extract year from folder name: "Movie Title (YYYY)"
    if [[ "$dir_name" =~ \(([0-9]{4})\) ]]; then
        folder_year="${BASH_REMATCH[1]}"
        movie_title="${dir_name% (*}"
        
        echo "------------------------------------------------"
        echo "Checking: $movie_title"
        echo "Folder Year: $folder_year"

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
            elif [[ "$radarr_year" -eq "$folder_year" ]]; then
                echo "[$label] Result: MATCH ($radarr_year)"
            else
                echo "[$label] Result: MISMATCH! (Radarr says $radarr_year)"
            fi
        }

        check_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
        check_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"

    else
        # Optional: uncomment if you want to see which folders failed the regex
        # echo "Skipping: $dir_name (Year pattern not found)"
        continue
    fi
done

echo "------------------------------------------------"
echo "Scan complete."
