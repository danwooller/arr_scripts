# Arr Scripts Automation
Automated processing for "Linux ISOs" using HandBrakeCLI, featuring resolution-aware transcoding (1080p/4K) and forced subtitle extraction/embedding.

---

## 📂 Repository Contents

### 🛠 Core Media Tools
| File | Description |
| :--- | :--- |
| **monitor_convert.sh** | Monitors folders for unconverted media, detects resolution (1080p/4K), and transcodes via HandBrakeCLI. |
| **merge_forced_subtitles.sh** | Syncs media files with external subtitles and remuxes to MKV with "Forced" flags set. |
| **convert_mkv.sh** | Monitors for `.mp4` and `.m4v` files and remuxes them to `.mkv` containers. |
| **cert_monitor.sh** | Validates SSL certificates and generates `.p12` bundles for Plex Media Server. |

### 🔧 System & Maintenance Tools
| File | Description |
| :--- | :--- |
| **git_push.sh** | Pushes local edits to GitHub. Auto-handles identity, branch naming, and index cleanup. |
| **update_script.sh** | The primary deployment tool. Installs scripts to `/usr/local/bin` and manages services. |
| **git_pull_install.sh** | Specialized installer: Syncs script, sets permissions, and configures the systemd service. |
| **common_functions.sh** | Global include file for standardized logging and dependency management. |
| ***.service** | Systemd unit templates for running any of the above as background daemons. |

---

## 🚀 Key Workflows

### 1. Syncing Local Edits to GitHub
Use this when you've modified a script on your server and want to back it up to your repository.
```bash
./git_push.sh <filename.sh>
