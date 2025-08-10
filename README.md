# OpenWrt E8450 Fleet Management

Automated management system for Linksys E8450 (UBI) routers running OpenWrt 24.10.x.

## Hardware

**Linksys E8450 (UBI)** - MediaTek MT7622 based WiFi 6 router
- 512MB RAM, 128MB NAND flash
- 2.4GHz 802.11ax 2x2, 5GHz 802.11ax 2x2
- 4x Gigabit LAN, 1x Gigabit WAN
- Running OpenWrt UBI variant (special bootloader required)

## Network Architecture

- **primary-ap** (192.168.1.1): Primary gateway, DHCP server, firewall
- **secondary-ap** (192.168.1.2): Network extension via WDS wireless backhaul

Target: OpenWrt latest stable release

## Quick Start Guide

### Check for Updates
```bash
./scripts/check_updates.sh
```

### Backup Both Routers
```bash
./scripts/backup_all.sh
```

### Apply Package Updates
```bash
./scripts/update_packages.sh secondary-ap  # Test first
./scripts/update_packages.sh primary-ap    # Then production
```

## Directory Structure

```
.
├── README.md
├── scripts/
│   ├── check_updates.sh     # Check for available updates
│   ├── backup_all.sh        # Backup both routers
│   └── update_packages.sh   # Apply package updates
├── private/                  # Private data (symlinked)
│   ├── setup-private-data.sh # Setup script for symlinks
│   ├── device-data/
│   │   ├── primary-ap/
│   │   │   ├── config/      # UCI config exports
│   │   │   ├── backups/     # Full system backups
│   │   │   └── device_info.txt  # Device information
│   │   └── secondary-ap/
│   │       ├── config/
│   │       ├── backups/
│   │       └── device_info.txt
│   └── logs/
│       └── update_[timestamp].log
└── notes/
    ├── OpenWrt_Forum_Linksys_E8450-distilled.md  # Community knowledge base
    ├── UPGRADE_PROCESS.md        # Detailed update procedures
    ├── README-tailscale-exit-node.md  # Tailscale VPN setup
    └── private-data-info.md     # Private data structure documentation
```

## Key Configuration Areas

Based on 4+ years of community experience from the OpenWrt forums (see [distilled notes](notes/OpenWrt_Forum_Linksys_E8450-distilled.md)):

### Critical Issues & Solutions
- **Reboot to Recovery Loop**: Device boots into recovery mode after crash - perform cold boot (30s power off) to clear pstore logs
- **I/O Errors on mtdblock2**: Harmless ECC errors from factory partition - can be safely ignored
- **Maximum Stability Tips**: Enable IRQBalance, avoid 802.11r with Apple devices, disable hardware flow offloading

### Performance & Optimization
- **Memory Management**: 512MB RAM requires careful management - use zram-swap, disable unused services
- **WiFi 6 Tuning**: Use 80MHz channels for stability, enable MU-MIMO, configure OFDMA based on client density
- **SQM/QoS**: E8450 handles ~600Mbps with cake, ~800Mbps with fq_codel

### Network Features
- **VLANs & Segmentation**: Guest networks, IoT isolation, multiple SSIDs with different security zones
- **DNS & Ad-blocking**: simple-adblock (lightweight) or AdGuard Home (feature-rich, 100-150MB RAM)
- **IPv6 & CGNAT**: Full IPv6 support with prefix delegation, DS-Lite, 464XLAT compatibility

### Mesh Networking
- **WDS**: Most reliable for 2-3 nodes, simple setup
- **802.11s**: Better for 4+ nodes, requires tuning
- **Channel Selection**: Use non-DFS channels (36-48, 149-165), 80MHz width recommended

### Popular Add-ons
- Network-wide VPN (WireGuard ~200Mbps, OpenVPN ~50Mbps)
- Home automation hub (MQTT, Zigbee2MQTT)
- Network monitoring (Netdata, vnstat, nlbwmon)
- USB LTE/5G failover with mwan3

## SSH Configuration

Add to `~/.ssh/config`:

```
Host primary-ap
    HostName 192.168.1.1
    User root
    Port 22
    StrictHostKeyChecking accept-new

Host secondary-ap
    HostName 192.168.1.2
    User root
    Port 22
    StrictHostKeyChecking accept-new
```

## Critical E8450 UBI Notes

**WARNING**: The E8450 UBI variant requires special handling:
- Never use non-UBI firmware on UBI devices
- Always use sysupgrade images, not factory images
- The device uses a special bootloader (U-Boot 2022.x with UBI support)
- Power loss during upgrade can brick the device - use UPS if possible

## Backup & Recovery

### Create Full Backup
```bash
DEVICE="primary-ap"  # or "secondary-ap"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup via LuCI method (recommended)
ssh $DEVICE "sysupgrade -b /tmp/backup.tar.gz"
scp $DEVICE:/tmp/backup.tar.gz ./private/device-data/$DEVICE/backups/${TIMESTAMP}_backup.tar.gz

# Also backup individual config files
for config in network wireless firewall dhcp system; do
    ssh $DEVICE "uci export $config" > ./private/device-data/$DEVICE/config/$config
done
```

### Restore from Backup
```bash
# Upload and restore backup
scp ./private/device-data/$DEVICE/backups/backup.tar.gz $DEVICE:/tmp/
ssh $DEVICE "sysupgrade -r /tmp/backup.tar.gz && reboot"
```

## Maintenance & Updates

### Tools Installed
- **owut** - CLI tool for firmware updates
- **luci-app-attendedsysupgrade** - Web UI for firmware updates (System > Attended Sysupgrade)

### Update Strategy
1. Wait 2-4 weeks after release for community feedback
2. Check forum for E8450-specific issues
3. Test on secondary-ap first
4. Keep previous firmware file for rollback

### Monthly Maintenance Routine
See [UPGRADE_PROCESS.md](notes/UPGRADE_PROCESS.md#monthly-maintenance-routine) for detailed procedures:
- Package updates
- Configuration backups
- Log review
- Performance monitoring

### Recommended Stable Releases
- **23.05.5**: Most stable overall, excellent for production
- **22.03.7**: Rock-solid but lacks newer features
- **24.10.2**: Current stable with good stability after bug fixes
- Avoid .0 releases and snapshots for production use

## Monitoring & Health Checks

### Quick Health Check
```bash
DEVICE="primary-ap"
ssh $DEVICE << 'EOF'
echo "=== System Info ==="
uptime
free -m
df -h
echo "=== Network Status ==="
ip -br addr
ip -br link
echo "=== WiFi Status ==="
ubus call network.wireless status
echo "=== Recent Errors ==="
logread | tail -20 | grep -i error
EOF
```

### Performance Monitoring
```bash
# Check CPU usage during transfers
ssh $DEVICE "top -d 1 | grep -E 'si|sirq'"

# Monitor WiFi quality
ssh $DEVICE "iw dev wlan1 station dump | grep -E 'signal|tx bitrate'"

# Check memory usage
ssh $DEVICE "free -m && ps | awk '{print $5 \" \" $1 \" \" $9}' | sort -rn | head -10"
```

## Common Commands Reference

```bash
# Show current version
ubus call system board

# Show wireless status
ubus call network.wireless status

# Restart services
/etc/init.d/network restart
/etc/init.d/firewall restart
wifi reload

# Package management
opkg update
opkg list-upgradable
opkg upgrade <package>

# Configuration
uci show
uci set network.lan.ipaddr='192.168.1.1'
uci commit network

# Logs
logread -f  # Follow log
dmesg       # Kernel messages
```

## Security Considerations

- All sensitive data (backups, configs, logs) is excluded via `.gitignore`
- Use strong passwords for WiFi and admin access
- Keep firmware and packages updated
- Consider network segmentation for IoT devices
- Enable firewall logging for suspicious activity monitoring

## Resources & Documentation

- [OpenWrt E8450 Device Page](https://openwrt.org/toh/linksys/e8450)
- [E8450 UBI Installer](https://github.com/dangowrt/owrt-ubi-installer)
- [OpenWrt Forum E8450 Thread](https://forum.openwrt.org/t/belkin-rt3200-linksys-e8450-wifi-ax-discussion/94302)
- [Sysupgrade Documentation](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)
- [Community Knowledge Base](notes/OpenWrt_Forum_Linksys_E8450-distilled.md) - Distilled from 4+ years of forum discussions

## Important Reminders

1. **Never** interrupt power during firmware upgrade
2. **Always** keep backups before making changes
3. **Test** on secondary-ap device before upgrading primary-ap
4. **Document** any custom configurations or scripts
5. **Monitor** logs after upgrade for issues