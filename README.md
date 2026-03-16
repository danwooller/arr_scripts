# Arr Scripts Automation
Automated processing for "Linux ISOs" using HandBrakeCLI, featuring resolution-aware transcoding (1080p/4K) and forced subtitle extraction/embedding.

---

## 📂 Repository Contents

## 🛠 Core Media Tools
| File | Description |
| :--- | :--- |
| [**DW_cert_monitor.sh**](./DW_cert_monitor.sh) | Validates SSL certificates and generates `.p12` bundles for Plex Media Server. _Running on ubuntu24_ |
| [**DW_check_media_stack.sh**](./DW_check_media_stack.sh) | Checks availability of docker services and reports to Home Assistant. _Running on ubuntu9_ |
| [**DW_clean_malicious.sh**](./DW_clean_malicious.sh) | Scans convert directories looking for .exe. and .rar files, removes torrents and deletes files. _Running on ubuntu9_ |
| [**DW_concat_mp4.sh**](./DW_concat_mp4.sh) | Merges two mp4 files using ffmpeg into a single file and outputs to the completed directory. _Running on ubuntu9 & ubuntu24_ |
| [**DW_convert_mkv.sh**](./DW_convert_mkv.sh) | Monitors for mp4/m4v and converts them to mkv. _Running on ubuntu9_ |
| [**DW_done.sh**](./DW_done.sh) | Terminal monitor for DW_moniotr_convert.sh progress. _Running on pi14, pi16 & ubuntu9_ |
| [**DW_install_sort_tv.sh**](./DW_install_sort_tv.sh) | Installs a custome sorttv as a service. Includes patched for Ubutnu 24.04. _Running on ubuntu24_ |
| [**DW_merge_forced_subtitles.sh**](./DW_merge_forced_subtitles.sh) | Syncs media files with external subtitles and remuxes to MKV with "Forced" flags set. _Running on ubuntu9_ |
| [**DW_mkv_movies_title.sh**](./DW_mkv_movies_title.sh) | Loops through TV directories and matched the video title to the parent directory name. _Running on ubuntu9_ |
| [**DW_mkv_set_eng.sh**](./DW_mkv_set_eng.sh) | Checks mkv files in $1 and sets audio and subtitles to English if they are unset. _Running on ubuntu9_ |
| [**DW_mkv_tv_shows_title.sh**](./DW_mkv_tv_shows_title.sh) | Loops through TV directories and matched the video title to the filename. _Running on ubuntu9_ |
| [**DW_monitor_convert.sh**](./DW_monitor_convert.sh) | Monitors folders for unconverted media, detects resolution (480p/576p/1080p/4K), and transcodes via HandBrakeCLI. _Running on pi14, pi16 & ubuntu9_ |
| [**DW_monitor_movie_subtitles.sh**](./DW_monitor_movie_subtitles.sh) | Monitors $SOURCE_DIR for mkv files and processes the audio and subtitles, keeping English subs for non-English audio and stripping non-forced subtitles from English audio. _Running on ubuntu9_ |
| [**DW_move_movies_synology.sh**](./DW_move_movies_synology.sh) | Monitors the movies folder on the secondary server (synology) and checks the primary (truenas) for duplicates (indicating a REPACK) and moves them. _Running on ubuntu24_ |
| [**DW_move_tv_shows_synology.sh**](./DW_move_tv_shows_synology.sh) | Monitors the tv shows folder on the secondary server (synology) and checks the primary (truenas) for duplicate show folders (indicating a REPACK or new episodes) and moves them. _Running on ubuntu24_ |
| [**DW_move_single_tv_show_synology.sh**](./DW_move_single_tv_show_synology.sh) | Moves the tv show folder specified by $1 and moves it to the secondary server (synology) only if it exists. _Running on ubuntu9 & ubuntu24_ |
| [**DW_plex_update.sh**](./DW_plex_update.sh) | Triggers a library update on Plex, $1 is section ID and $2 is library name. _Running on ubuntu24_ |
| [**DW_rename_media.sh**](./DW_rename_media.sh) | Looks for obfuscated filesnames and tries to find NZB metadata to retore filename. _Running on ubuntu9_ |
| [**DW_restart_vpn.sh**](./DW_restart_vpn.sh) | Restarts the VPN and associated torrent containers. _Running on ubuntu9_ |
| [**DW_scan_corrupt_media.sh**](./DW_scan_corrupt_media.sh) | Scan directories in $1 looking for corrupted media files, marking an issue in Seer. _Running on ubuntu24_ |
| [**DW_scan_duplicate_episodes.sh**](./DW_scan_duplicate_episodes.sh) | Scan directories looking for duplicate episodes, marking an issue in Seer. _Running on ubuntu24_ |
| [**DW_scan_missing_episodes.sh**](./DW_scan_missing_episodes.sh) | Scan directories in $1 looking for gaps in episode numbering, marking an issue in Seer. _ubuntu24_ |
| [**DW_scan_movie_year.sh**](./DW_scan_movie_year.sh) | Scan directories in $1 looking for mismatches between the movie folder year and Radarr. Corrects folder and updates Radarr. _ubuntu24_ |
| [**DW_sort_tv.sh**](./DW_sort_tv.sh) | Wraps the Perl script sorttv in a service. Currently has problems with Daily Show/Colbert on Ubutnu 24.04. _ubuntu24_ |
| [**update-docker.sh**](./update-docker.sh) | Runs a linux update then backs up the containers to the network while updating. _ubuntu9 ubuntu24_ |
| [**DW_usenet_org.sh**](./DW_usenet_org.sh) | Looks for media files without readable filenames and attempts to convert them using folder names. _ubuntu9_ |

### 🔧 System & Maintenance Tools
| File | Description |
| :--- | :--- |
| [**DW_common_functions.sh**](./DW_common_functions.sh) | Global include file for standardised logging and dependency management. |
| **common_keys.txt** | Sensitive keys and mappings, called by common_functions.sh. |
| [**DW_common_seer_issue.sh**](./DW_common_seer_issue.s) | Function for managing issues on Seer, called by common_functions.sh. |
| [**git_pull.sh**](./git_pull.sh) | Pulls $1 from GitHub. Copies to /usr/local/bin and sets permissions. |
| [**git_pull_install.sh**](./git_pull_install.sh) | Specialized installer: Syncs script, sets permissions, and configures the systemd service. |
| [**git_push.sh**](./git_push.sh) | Pushes local edits to GitHub. Auto-handles identity, branch naming, and index cleanup. |
| ***.service** | Systemd unit templates for running any of the above as background daemons. |
| **xxx.sh** | xxx. |
---

## 🚀 Key Workflows

### 1. Syncing Local Edits to GitHub
Use this when you've modified a script on your server and want to back it up to your repository.
```bash
sudo ./git_push.sh <filename.sh>
```
Metric Standards: Logs and measurements (file sizes, temps) utilize metric units (MB/GB/°C).

Self-Cleaning: If no actual changes are detected, the script resets the index to prevent "dirty" rebase errors.

### 2. Deploying to System / Updating Services
Use this to move a script from the repo folder into the system path and restart its background service.

```bash
sudo ./git_pull_install.sh <filename.sh>
```
Use this to move a script from the repo folder into the system path (for scripts that run manually or in cron).

```bash
sudo ./git_pull.sh <filename.sh>
```
Service Mapping: Automatically maps script_name.sh to script_name.service.

Lifecycle: Automates cp, chmod, daemon-reload, and systemctl restart.

🛠 Installation & Requirements
Setup on a New Machine

### 3. Clone the repository
```bash
sudo git clone https://github.com/danwooller/arr_scripts.git ~/arr_scripts
cd ~/arr_scripts
```
### 4. Set permissions
```bash
sudo chmod +x *.sh
```
### 5. First-time Push (Configures GitHub Auth)
When prompted, use your GitHub Username and Personal Access Token (PAT). Ensure common_keys.txt are copied to /usr/local/bin.
```bash
sudo ./git_push.sh git_push.sh
```
System Requirements
Git:
```bash
sudo apt install git -y
```
Systemd: Standard on Ubuntu/Debian/Raspbian.

⚙️ Service Configuration Template
When creating a new background service, use this logic within your .service files to ensure compatibility with git_pull_install.sh:

Ini, TOML
```bash
[Unit]
Description=Service for %i
After=network.target

[Service]
User=dan
Group=dan
ExecStart=/usr/local/bin/YOUR_SCRIPT_NAME.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

📝 Troubleshooting
Logs: View live service output: journalctl -xefu <service_name> -f

Permissions: If a script fails to run, verify ownership: ls -l /usr/local/bin/

Git Conflicts: If git_push.sh fails due to remote changes, the script is designed to fetch and reset --hard to ensure your local environment stays synced with the "source of truth" on GitHub.
