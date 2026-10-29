# 🔐 Secure Vault Manager 2.0

A portable, terminal-based encrypted folder manager using `gocryptfs`.

## Installation (Global Command)

To use Secure Vault Manager as a system-wide command (`secmgr`), follow these steps:

### 1. Copy to System Library
Move the project folder to a permanent location:
```bash
sudo mkdir -p /usr/local/lib/secure_manager
sudo cp -r ./* /usr/local/lib/secure_manager/
```

### 2. Create Symlink
Create a shortcut in your bin directory:
```bash
sudo ln -sf /usr/local/lib/secure_manager/secure_manager.sh /usr/local/bin/secmgr
```

Now you can run the manager from anywhere by simply typing:
```bash
secmgr
```

---

## 🛠 Making Changes & Updating

If you make modifications to the code in your local development folder (e.g., in your Desktop directory) and want those changes to take effect in the `secmgr` command, you must update the system files:

### Update All Files
```bash
sudo cp -r ./* /usr/local/lib/secure_manager/
```

### Update Only Main Script
```bash
sudo cp secure_manager.sh /usr/local/lib/secure_manager/
```

### Update Only Library Files
```bash
sudo cp -r lib/* /usr/local/lib/secure_manager/lib/
```

---

## Requirements
- **gocryptfs**: The encryption engine.
- **fuse3** (or fuse2): Required for mounting.
- **dbus-monitor**: Required for the Auto-Lock Guard service.
