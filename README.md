A collection of bash scripts to process my growing stash of Linux ISOs, with HandBrake conversion including support for extracting and embedding Forced subtitles.

---

## 📂 Repository Contents

| File | Description |
| :--- | :--- |
| **common_functions.sh** | Include file to maintain common logging and dependancy installation. |
| **git_pull.sh** | Pulls $1 from GitHub. Copies to /usr/local/bin and sets permissions. |
| **git_pull_install.sh** | Pulls $1 from GitHub. Copies to /usr/local/bin, sets permissions then pulls the associated service file, installs if necessary and starts. |
| **git_push.sh** | Safely pushes local changes to GitHub. Handles identity (user/email), renames branches to `main`, and resolves "unstaged changes" errors during rebasing. |
| **xxx.sh** | xxx. |
| **cert_monitor.sh** | Ensure the certificate is valid and a P12 generated for a Plex MEdia Server. |
| **convert_mkv.sh** | Monitors a folder for mp4 and m4v files and converts them to mkv. |
| **merge_forced_subtitles.sh** | Monitors a folder for media files and associated subtitles then converts them to mkv setting the subtitle title to Forced. |
| **monitor_convert.sh** | # Monitors a folder looking for unconverted Linux ISOs, copies them to a local folder, determines whether the file is 1080p or 4K and converts the file using HandBrakeCLIbefore copying back to the network for further sorting. |
| **update_script.sh** | Pulls latest repo changes, installs a specified script to `/usr/local/bin`, and automatically installs/restarts the corresponding systemd service. |
| **convert_mkv.sh** | Media processing script (e.g., transcoding or file management). |
| ***.service** | Systemd unit files that allow your `.sh` scripts to run as background services. |

---

## 🚀 Key Workflows

### 1. Pushing Local Changes
Use this when you have edited a script on your server and want to save it to GitHub.
```bash
./git_push.sh <filename.sh>

Metric Support: Note that all logs and internal measurements in these scripts are configured to use metric units (e.g., file sizes in MB/GB, temperatures in Celsius) per system preferences.

Automatic Cleanup: If you haven't actually changed the file, the script will automatically reset your index to keep your git pull clean.

2. Updating & Installing Services
Use this to deploy a script and its service file to the system.

Bash
./update_script.sh convert_mkv.sh
Service Detection: The script automatically strips extensions. If you provide convert_mkv.sh, it looks for convert_mkv.service in the repo.

Auto-Restart: It performs a daemon-reload and systemctl restart automatically.

🛠 Installation on a New Machine
Clone the repo:

Bash
git clone https://github.com/danwooller/arr_scripts.git ~/arr_scripts
cd ~/arr_scripts
chmod +x *.sh
Configure GitHub Identity:
The first time you run git_push.sh, you will be prompted for your GitHub username and Personal Access Token. The script will store these securely using credential.helper store.

⚙️ Requirements
Git: sudo apt install git

Systemd: Standard on Ubuntu/Raspbian.

Permissions: Scripts should be run with sudo privileges to allow moving files to /usr/local/bin and managing services.

Note: If you add new .sh scripts, ensure you also create a corresponding .service file (without the .sh in the filename) if you intend for it to run in the background.

