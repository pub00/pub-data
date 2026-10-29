# 🌐 G-Manager

**G-Manager** is a terminal-based Google Chrome profile switcher designed to work seamlessly with encrypted vaults. It allows you to isolate different Google accounts into their own encrypted directories and swap between them instantly using symbolic links.

## 🚀 Quick Start
1.  **Unlock your vault** using [Secure Manager](../secure_%20manager/).
2.  Run the manager:
    ```bash
    bash g_manager.sh
    ```
3.  Follow the on-screen menu to create or switch profiles.

## 🛠 Features
- **Multi-Account Isolation**: Each account has its own isolated `Default` directory.
- **Encrypted at Rest**: Works with `gocryptfs` vaults via Secure Manager.
- **Distribution Agnostic**: Tested and optimized for Ubuntu and Arch Linux.
- **No GUI Dependencies**: Pure Bash/Terminal interface.

## 📖 Documentation
- [Troubleshooting & Migration Guide](TROUBLESHOOTING.md): Read this if you are moving from another system or encountering "Incorrect Password" errors.

## 🌍 Global Installation
To run G-Manager from anywhere using the keyword `a3ctl`, follow these steps:

1.  **Install the files:**
    ```bash
    sudo mkdir -p /usr/local/lib/G-manager
    sudo cp -r . /usr/local/lib/G-manager/
    ```

2.  **Create the global link:**
    ```bash
    sudo ln -sf /usr/local/lib/G-manager/g_manager.sh /usr/local/bin/a3ctl
    sudo chmod +x /usr/local/lib/G-manager/g_manager.sh
    ```

3.  **Run it:**
    ```bash
    a3ctl
    ```

### 🔄 Updating
To update the global installation with your latest code changes:
```bash
sudo cp -r . /usr/local/lib/G-manager/
```

---
*Built for security and privacy.*
