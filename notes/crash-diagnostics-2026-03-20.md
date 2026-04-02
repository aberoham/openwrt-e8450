# Downstairs AP Kernel Crash & Recovery - 2026-03-20

## Incident Summary

On March 20, 2026 at approximately 17:09 UTC, the downstairs AP (hostname: `downstairs`) experienced a kernel crash. The router rebooted into U-Boot's **pstore recovery mode**, which boots an initramfs recovery image instead of the normal production firmware. This left the router in a "limp mode" state with default configuration.

The issue was diagnosed and resolved on March 31, 2026.

## Symptoms Observed

- Router accessible at **192.168.1.1** (default IP) instead of its configured LAN IP
- **New SSH host key** (old key lost because overlay wasn't mounted)
- **No root password** set (factory default)
- Hostname was `OpenWrt` instead of `downstairs`
- Banner showed `OpenWrt 24.10.0` (recovery image version, not the production 24.10.5)

## Root Cause Analysis

### The pstore Recovery Boot Mechanism

The E8450 UBI U-Boot has a safety mechanism in its `bootcmd`:

```
bootcmd=if pstore check ; then run boot_recovery ; else run boot_ubi ; fi
```

When the kernel crashes, crash data is written to a reserved RAM region (ramoops/pstore at `0x42ff0000`, 64 KiB). On the next boot, U-Boot's `pstore check` detects this data and automatically boots the **recovery initramfs image** (from UBI volume `recovery`) instead of the normal production firmware (from UBI volume `fit`).

### What Happened Step by Step

1. **March 20 ~17:09**: Kernel crash occurred (cause unknown - crash logs were corrupted)
2. **Crash data written to pstore** (ramoops region in NAND-backed RAM area)
3. **Router rebooted** (either automatic or power cycle)
4. **U-Boot ran `pstore check`** -> found crash data -> ran `boot_recovery`
5. **Recovery image booted**: initramfs-only, runs entirely from RAM (tmpfs)
6. **Overlay never mounted**: Recovery mode's `mount_root` detects tmpfs root and skips overlay setup
7. **Router appeared as factory-default**: 192.168.1.1, no password, hostname "OpenWrt"

### Why the Overlay Wasn't Mounted

The recovery image boots as initramfs (the entire rootfs is embedded in the kernel and extracted to tmpfs). In this mode:

- Root filesystem: `tmpfs / tmpfs rw,relatime` (RAM-only)
- No `/dev/root` device exists
- `mount_root start` returns exit code 255 (detects tmpfs root, refuses to set up overlay)
- The `80_mount_root` preinit script checks `[ "$INITRAMFS" = "1" ]` and skips overlay setup

The production firmware boots differently:
- Root filesystem: squashfs from `/dev/fit0` (mapped from UBI volume `fit`)
- `mount_root` detects squashfs root, mounts UBIFS `rootfs_data` as overlay
- OverlayFS merges squashfs (read-only) + UBIFS (read-write) as `/`

## Diagnostic Steps Performed

### 1. Initial Assessment
```
ssh root@192.168.1.1
# Observed: no password, default hostname, OpenWrt 24.10.0 banner
```

### 2. System State Check
```
uptime                    # Up ~1 hour
df -h                     # Only tmpfs mounts, no persistent storage
mount | grep overlay      # Empty - no overlay mounted
mount | grep ubi          # Empty - no UBI volumes mounted
```

### 3. UBI Health Check
```
ubinfo -a
# Result: 8 volumes, all State: OK
# 1 bad PEB (normal for NAND), erase counter max: 3 (very low wear)
# Volume 7 (rootfs_data): 93 MiB, dynamic, OK
```

### 4. Manual Overlay Mount Test
```
mkdir -p /tmp/test_overlay
mount -t ubifs ubi0:rootfs_data /tmp/test_overlay
# SUCCESS - overlay data intact
ls /tmp/test_overlay/upper/etc/config/
# All config files present, last modified March 20
cat /tmp/test_overlay/upper/etc/config/system | grep hostname
# hostname 'downstairs' - confirmed config intact
```

### 5. Squashfs Integrity Check
```
mkdir -p /tmp/test_rom
mount -t squashfs /dev/fit0 /tmp/test_rom
# SUCCESS - squashfs mounts fine
dd if=/dev/fit0 bs=4 count=1 | hexdump -C
# Shows 'hsqs' magic - valid squashfs
```

### 6. Identified Root Cause
```
# U-Boot environment revealed:
fw_printenv bootcmd
# bootcmd=if pstore check ; then run boot_recovery ; else run boot_ubi ; fi

# Kernel dmesg showed:
# ramoops: found existing invalid buffer, size 0, start 2048
# pstore: zlib_inflate() failed, ret = -3!

# Pstore had crash data:
ls /sys/fs/pstore/
# dmesg-ramoops-0.enc.z  (dated Mar 20 17:09)
# dmesg-ramoops-1.enc.z  (dated Mar 20 17:09)
```

### 7. UBIFS Journal Recovery
When manually mounting the overlay, the kernel logged:
```
UBIFS (ubi0:7): recovery needed
UBIFS (ubi0:7): recovery completed
```
This confirmed an unclean shutdown (crash) on March 20.

## Resolution

### Steps Taken
1. **Saved crash logs** to `private/logs/crash-2026-03-20/` (compressed pstore dumps, though data was corrupted and unreadable)
2. **Cleared pstore entries**: `rm /sys/fs/pstore/dmesg-ramoops-*.enc.z`
3. **Rebooted**: U-Boot found clean pstore -> ran `boot_ubi` -> production firmware booted normally
4. **Verified recovery**: hostname `downstairs`, overlay mounted, config restored

### Post-Recovery Upgrade
Upgraded both APs from 24.10.5 (kernel 6.6.119) to 24.10.6 (kernel 6.6.127) to address potential kernel bugs that may have caused the original crash.

## Key Learnings

### The pstore Recovery Boot is a Feature, Not a Bug
U-Boot's pstore check is a safety mechanism. If the kernel keeps crashing, it boots into recovery mode to allow diagnosis/reflashing. However, it can be triggered by a single crash and requires manual intervention (clearing pstore) to resume normal boot.

### Recovery Mode Gotchas
- Recovery image version (24.10.0) differs from production (24.10.5) - the recovery image in the `recovery` UBI volume is not updated by sysupgrade
- Default network config (192.168.1.1) may conflict with existing network topology
- No password means anyone on the LAN can access the router

### Data Survival
All overlay data (config, installed packages, customizations) survived the crash intact. The UBIFS journal recovery mechanism handled the unclean shutdown gracefully.

## UBI Volume Layout Reference

| Vol | Name | Size | Type | Purpose |
|-----|------|------|------|---------|
| 0 | fip | 1.0 MiB | static | U-Boot FIP (firmware image package) |
| 1 | factory | 620 KiB | static | Factory calibration data |
| 2 | ubootenv | 124 KiB | dynamic | U-Boot environment |
| 3 | ubootenv2 | 124 KiB | dynamic | U-Boot environment backup |
| 4 | recovery | 7.0 MiB | dynamic | Recovery initramfs image |
| 5 | fit | 10.2 MiB | dynamic | Production FIT image (kernel + squashfs) |
| 6 | boot_backup | 8.1 MiB | dynamic | Boot backup |
| 7 | rootfs_data | 93.0 MiB | dynamic | Overlay filesystem (UBIFS) |

## Files Referenced

- `private/logs/crash-2026-03-20/dmesg-ramoops-0.enc.z` - Crash dump 1 (corrupted)
- `private/logs/crash-2026-03-20/dmesg-ramoops-1.enc.z` - Crash dump 2 (corrupted)
- `private/old-backups/backup-downstairs-2026-03-31.tar.gz` - Pre-upgrade backup
- `private/old-backups/packages-downstairs-2026-03-31.txt` - Package list at time of upgrade
