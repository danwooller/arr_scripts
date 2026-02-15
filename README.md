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


