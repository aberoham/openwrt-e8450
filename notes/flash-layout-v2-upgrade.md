# E8450 Flash Layout v1.0 to v2.0 Upgrade

## Summary

How to upgrade an E8450 (UBI) from flash layout v1.0 to v2.0, required for OpenWrt 24.10.5+.

## Problem

Attended Sysupgrade fails with:
```
The device is supported, but this image is incompatible for sysupgrade based on the image version (1.0->2.0).
SPI-NAND flash layout changes require bootloader update. Please run the UBI installer version 1.1.0+ (unsigned) first.
```

OpenWrt releases after February 2024 require flash layout v2.0. Devices on v1.0 cannot use normal sysupgrade.

## Backup First

```bash
# Configuration backup
ssh root@192.168.1.1 "sysupgrade -b /tmp/backup.tar.gz"
scp -O root@192.168.1.1:/tmp/backup.tar.gz ./

# Factory partition backup (WiFi calibration - irreplaceable)
ssh root@192.168.1.1 "dd if=/dev/ubi0_1 of=/tmp/factory-backup.bin bs=1024"
scp -O root@192.168.1.1:/tmp/factory-backup.bin ./
```

## Upgrade Procedure

### Step 1: Download UBI Installer

Get `openwrt-24.10.0-mediatek-mt7622-linksys_e8450-ubi-initramfs-recovery-installer.itb` from:
https://github.com/dangowrt/owrt-ubi-installer/releases

This installer includes new bootloader and flash layout v2.0.

### Step 2: Flash via LuCI

1. System → Backup / Flash Firmware
2. Upload the installer `.itb` file
3. **Check "Force upgrade"** (required - installer lacks standard metadata)
4. Uncheck "Keep settings" (won't persist anyway due to layout change)
5. Flash and wait

### Step 3: Handle Recovery Mode Boot

The router may boot into recovery/initramfs mode due to pstore panic records.

Check for recovery mode:
- Web UI shows "System running in recovery (initramfs) mode"
- Root filesystem is tmpfs

Fix:
```bash
ssh root@192.168.1.1 "rm -f /sys/fs/pstore/*; reboot"
```

### Step 4: Flash Sysupgrade from Recovery

If stuck in recovery mode, flash the sysupgrade image:

```bash
curl -L -o sysupgrade.itb \
  "https://github.com/dangowrt/owrt-ubi-installer/releases/download/v1.1.4/openwrt-24.10.0-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.itb"

scp -O sysupgrade.itb root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "sysupgrade -n /tmp/sysupgrade.itb"
```

### Step 5: Restore Configuration

After reboot to default 192.168.1.1:

```bash
scp -O backup.tar.gz root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "sysupgrade -r /tmp/backup.tar.gz && reboot"
```

### Step 6: Set compat_version

Restored configs from v1.0 systems lack the compat_version setting:

```bash
ssh root@192.168.1.1 "uci set system.@system[0].compat_version='2.0'; uci commit system"
```

### Step 7: Upgrade to Target Version

Now normal sysupgrade works:

```bash
curl -L -o openwrt-24.10.5.itb \
  "https://downloads.openwrt.org/releases/24.10.5/targets/mediatek/mt7622/openwrt-24.10.5-mediatek-mt7622-linksys_e8450-ubi-squashfs-sysupgrade.itb"

scp -O openwrt-24.10.5.itb root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "sysupgrade /tmp/openwrt-24.10.5.itb"
```

## Post-Upgrade Fixes

### LuCI Theme Error
```bash
opkg update
opkg install luci-theme-openwrt-2020 luci-base --force-reinstall
/etc/init.d/uhttpd restart
```

### Reinstall Packages
Config backups don't include packages. Reinstall as needed:
```bash
opkg install luci-app-attendedsysupgrade
opkg install wpad-wolfssl  # if replacing wpad-basic-mbedtls
```

## Key Points

1. **Flash layout changes require UBI installer** - sysupgrade cannot update bootloader
2. **Pstore causes recovery loops** - clear with `rm -f /sys/fs/pstore/*`
3. **Installer boots to recovery first** - then flash sysupgrade to permanent storage
4. **Set compat_version after restore** - required for future upgrades
5. **Packages need reinstalling** - backups only contain config files
6. **Force upgrade required** - installer lacks sysupgrade metadata

## References

- [UBI Installer Releases](https://github.com/dangowrt/owrt-ubi-installer/releases)
- [OpenWrt E8450 Device Page](https://openwrt.org/toh/linksys/e8450)
