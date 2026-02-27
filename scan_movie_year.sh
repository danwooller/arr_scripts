#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# --- Configuration ---
TARGET_DIR="${1:-/mnt/media/Movies}"

# --- Script Logic ---
echo "Scanning directories in: $TARGET_DIR"

# Iterate through each folder
for dir in "$TARGET_DIR"/*/ ; do
    # Strip trailing slash
    dir_name=$(basename "$dir")

    # Extract year from folder name: "Movie Title (YYYY)"
    if [[ "$dir_name" =~ \(([0-9]{4})\) ]]; then
        folder_year="${BASH_REMATCH[1]}"
        movie_title="${dir_name% (*}" # Remove the " (YYYY)" part for searching
        
        echo "------------------------------------------------"
        echo "Checking: $movie_title"
        echo "Folder Year: $folder_year"

        # Internal helper to query Radarr instances
        check_instance() {
            local base_url=$1
            local api_key=$2
            local label=$3

            # Query Radarr API for the movie title
            # We use /movie/lookup to find movies by name
            response=$(curl -s -G --data-urlencode "term=$movie_title" \
                "$base_url/movie/lookup" \
                -H "X-Api-Key: $api_key")

            # Extract the year from the first matching title result
            radarr_year=$(echo "$response" | jq -r ".[] | select(.title==\"$movie_title\") | .year" | head -n 1)

            if [[ -z "$radarr_year" || "$radarr_year" == "null" ]]; then
                echo "[$label] Result: Not found in database."
            elif [[ "$radarr_year" -eq "$folder_year" ]]; then
                echo "[$label] Result: MATCH ($radarr_year)"
            else
                echo "[$label] Result: MISMATCH! (Radarr says $radarr_year)"
            fi
        }

        # Execute check against both instances defined in common_functions.sh
        check_instance "$RADARR_API_BASE" "$RADARR_API_KEY" "Standard"
        check_instance "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "4K"

    else
        echo "Skipping: $dir_name (Year pattern not found)"
    fi
done

echo "------------------------------------------------"
echo "Scan complete."
