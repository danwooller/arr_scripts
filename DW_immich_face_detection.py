import requests
import time

# To run: python3 /usr/local/bin/DW_immich_face_detection.py
# --- CONFIGURATION ---
IMMICH_URL = "http://localhost:2283"
IMMICH_API_KEY = "npt5SLd0TG7u43MX0JvZo6lcZRTf1cmmwSm5OnbkxM"

BASE_URL = f"{IMMICH_URL.rstrip('/')}/api"
HEADERS = {
    "x-api-key": IMMICH_API_KEY,
    "Accept": "application/json",
    "Content-Type": "application/json"
}

STOP_WORDS = [
    " accept ", "accepts ", " attend ", "attends ", " arrive ", "arrives ",
    " backstage ", " during a ", " during the ", " general view".
    "members of ", "with the ", "("
]

def clean_name(text):
    cleaned = text
    earliest_index = len(cleaned)
    for word in STOP_WORDS:
        index = cleaned.lower().find(word.lower())
        if index != -1 and index < earliest_index:
            earliest_index = index
    return cleaned[:earliest_index].strip()

def run_legacy_sync():
    start_time = time.time()
    print(f"🚀 Starting Deep Scan on: {IMMICH_URL}")
    
    success_count = 0
    already_named = 0
    skipped_logic = 0
    processed_count = 0
    
    page = 1
    page_size = 1000 

    try:
        while True:
            # We use search/metadata because it handles large offsets better than the timeline
            payload = {
                "page": page,
                "size": page_size,
                "withPeople": True,
                "withExif": True
            }
            
            res = requests.post(f"{BASE_URL}/search/metadata", headers=HEADERS, json=payload)
            res.raise_for_status()
            data = res.json()
            
            # The structure for search results is usually data['assets']['items']
            assets = data.get('assets', {}).get('items', [])

            if not assets:
                print("\n🏁 Reach the end of the library. Sync complete.")
                break

            print(f"📡 Processing Page {page} ({len(assets)} assets)...")

            for asset in assets:
                processed_count += 1
                asset_id = asset['id']

                # The search endpoint often includes the data we need, 
                # saving us from making a second API call per photo!
                raw_info = (asset.get('description') or asset.get('exifInfo', {}).get('description', "")).strip()
                people = asset.get('people', [])

                if raw_info and len(people) == 1:
                    if "," not in raw_info and " and " not in raw_info.lower():
                        final_name = clean_name(raw_info)
                        if not final_name: continue

                        person = people[0]
                        if not person.get('name'):
                            # Update the person
                            person_id = person.get('id')
                            update_res = requests.put(
                                f"{BASE_URL}/people/{person_id}", 
                                headers=HEADERS, 
                                json={"name": final_name}
                            )
                            if update_res.status_code == 200:
                                print(f"✨ [{processed_count}] Named: '{final_name}'")
                                success_count += 1
                        else:
                            already_named += 1
                else:
                    skipped_logic += 1
            
            page += 1
            # Small break to let the database breathe
            time.sleep(0.1)

        total_time = time.time() - start_time
        print(f"\n✅ FULL SYNC FINISHED!")
        print(f"⏱️ Total Time: {total_time/60:.1f} minutes")
        print(f"👤 Names Assigned: {success_count}")
        print(f"⏭️ Already Named:  {already_named}")

    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    run_legacy_sync()
