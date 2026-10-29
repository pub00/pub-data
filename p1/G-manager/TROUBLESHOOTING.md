# 📖 G-Manager & Secure Vault Manager: Arch Linux Migration & Troubleshooting Guide

This guide documents the "suffering" and solutions encountered while moving this project from Ubuntu to Arch Linux. Use this as a quick reference for future setups.

---

## 🛠 1. Arch Linux Compatibility
The project uses standard Linux tools. On Arch, ensure these packages are installed:
- `coreutils` (mkdir, rm, mv, du, ln)
- `util-linux` (mountpoint)
- `procps-ng` (pgrep)
- `gocryptfs` (The encryption engine)
- `fuse3` (Required for mounting)

### Key Commands for Testing
If things feel "broken," verify these commands work in your terminal:
```bash
pgrep -x "google-chrome"   # Checks if Chrome is running
mountpoint -q /some/path   # Checks if a folder is a mounted vault
```

---

## 📂 2. Restoring Old Vault Data
If you have an encrypted `data/` folder from an old system, **DO NOT** use the "New Vault" option in the script. 

### The Correct Way to Restore:
1.  **Locate the Vault**: The default encrypted data path is `~/.chrome_profiles/data/`.
2.  **Transfer Files**: Copy **everything** from your old backup into that folder.
    *   **CRITICAL**: You must include `gocryptfs.conf` and `gocryptfs.diriv`. These files are the "lock" to your data.
3.  **Manual Verification**: Before using the script, test the data manually:
    ```bash
    mkdir -p /tmp/test_vault
    gocryptfs ~/.chrome_profiles/data /tmp/test_vault
    ```
4.  **Check Content**:
    ```bash
    ls /tmp/test_vault/   # You should see your decrypted profile folders here
    ```
5.  **Clean Up (Unmount)**:
    ```bash
    fusermount3 -u /tmp/test_vault/  # ALWAYS unmount before using the script
    ```

---

## 🔑 3. The "Incorrect Password" Nightmare
If `gocryptfs` says "Incorrect Password" but you are sure it's correct:
- **Keyboard Layout**: Arch might be using a different layout. Type your password into the terminal (visible) to verify `y/z` or special characters.
- **Master Key**: If you have the 25-word Master Key, you can recover with:
  `gocryptfs -masterkey="YOUR-KEY" . /tmp/test_vault`
- **Config Mismatch**: Ensure you copied the `gocryptfs.conf` from the **OLD** system. A new config file will never open old data, even with the same password.

---

## ⚙️ 4. Flexibility & Custom Paths
The project is now flexible. You can override paths without changing the code by setting environment variables:

| Variable | Default Path |
| :--- | :--- |
| `G_CHROME_CONFIG` | `~/.config/google-chrome` |
| `G_PROFILES_DIR` | `~/.chrome_profiles/chrome_profiles` |
| `G_CONFIG_DIR` | `~/.config/g_manager` |

**Example:**
```bash
G_PROFILES_DIR="/mnt/usb/vault" bash g_manager.sh
```

---

## 🚀 5. Startup Workflow
Every time you start:
1.  **Unlock the Vault**: Use Secure Manager to mount the encrypted data.
2.  **Launch G-Manager**: Run `bash g_manager.sh`.
3.  **Switch & Launch**: Choose your profile. The script will handle the symlink swap at `~/.config/google-chrome/Default`.

---
*Last Updated: 2026-05-16*
