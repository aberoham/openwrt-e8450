# Private Data Structure

This repository uses symlinks to a private data repository for sensitive information.

## Required Private Directories

All private data is now organized under the `private/` subdirectory:

### private/device-data/
Contains router configuration backups and UCI exports with sensitive network settings:
- Network configuration (IP addresses, routes, interfaces)
- WiFi credentials and settings
- Firewall rules and port forwards
- DHCP reservations and settings
- System passwords and access control

### private/binaries/ → firmware/
Contains OpenWrt firmware images and bootloader backups (~316MB):
- MTD partition backups (boot-backup/)
- Official OpenWrt releases (releases/)
- UBI installers and recovery images (installers/)

### private/old-backups/ → historical-backups/
Historical configuration backups from previous OpenWrt versions (2023-2025).

### private/logs/
Runtime and update logs from maintenance operations.

## Setup Instructions

### Option 1: Clone Private Repository
If you have access to the private repository:
```bash
./private/setup-private-data.sh
```

### Option 2: Create Your Own Private Data
If setting up your own environment:
1. Create directory structure at `~/openwrt-e8450-private/`
2. Place your configuration backups in appropriate directories
3. Run `./private/setup-private-data.sh` to create symlinks

## Directory Mapping

| Symlink in Main Repo | Points to Private Repo |
|---------------------|------------------------|
| `private/device-data/` | `~/openwrt-e8450-private/device-data/` |
| `private/binaries/` | `~/openwrt-e8450-private/firmware/` |
| `private/old-backups/` | `~/openwrt-e8450-private/historical-backups/` |
| `private/logs/` | `~/openwrt-e8450-private/logs/` |

## Security Notice

The private repository contains sensitive information:
- WiFi passwords
- Network configuration
- Access credentials
- Personal network topology

Never commit the private repository publicly.