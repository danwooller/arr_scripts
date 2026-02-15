A collection of bash scripts to process my growing stash of Linux ISOs, with HandBrake conversion including support for extracting and embedding Forced subtitles.

---

## 📂 Repository Contents

| File | Description |
| :--- | :--- |
| **git_push.sh** | Safely pushes local changes to GitHub. Handles identity (user/email), renames branches to `main`, and resolves "unstaged changes" errors during rebasing. |
| **update_script.sh** | Pulls latest repo changes, installs a specified script to `/usr/local/bin`, and automatically installs/restarts the corresponding systemd service. |
| **convert_mkv.sh** | Media processing script (e.g., transcoding or file management). |
| ***.service** | Systemd unit files that allow your `.sh` scripts to run as background services. |

---

## 🚀 Key Workflows

### 1. Pushing Local Changes
Use this when you have edited a script on your server and want to save it to GitHub.
```bash
./git_push.sh <filename.sh>


