# OpenWrt E8450 Upgrade Process & Strategy

## Overview

This document outlines the upgrade and maintenance strategy for the E8450 router fleet running OpenWrt 24.10.x. The strategy prioritizes stability, security, and minimal downtime while maintaining configuration consistency across devices.

## Device Roles

- **secondary-ap** (192.168.1.2): Test device for updates - all changes tested here first
- **primary-ap** (192.168.1.1): Production gateway - updated only after secondary-ap proven stable

## Update Types

### 1. Package Updates (Most Frequent)
Minor security patches and bug fixes to installed packages.
- **Frequency**: Monthly or as needed for security
- **Risk Level**: Low
- **Downtime**: < 1 minute per device
- **Method**: `opkg upgrade` or `update_packages.sh`

### 2. Minor Firmware Updates (e.g., 24.10.2 → 24.10.3)
Updates within the same major.minor version.
- **Frequency**: As released (typically every 2-3 months)
- **Risk Level**: Low-Medium
- **Downtime**: 3-5 minutes per device
- **Method**: Attended Sysupgrade (owut/LuCI)

### 3. Major Firmware Updates (e.g., 24.10 → 25.x)
Major version upgrades with potential breaking changes.
- **Frequency**: Annually or as needed
- **Risk Level**: High
- **Downtime**: 10-30 minutes per device
- **Method**: Manual sysupgrade with UBI images

## Standard Update Procedure

### Pre-Update Checklist
- [ ] Check current versions: `ssh [device] "cat /etc/openwrt_release"`
- [ ] Review changelog for breaking changes
- [ ] Schedule maintenance window (if production)
- [ ] Ensure UPS power protection available

### Step 1: Check for Updates
```bash
./scripts/check_updates.sh
```
This will show available package and firmware updates for both routers.

### Step 2: Create Backups
```bash
./scripts/backup_all.sh
```
Always backup before any changes. Backups stored in `private/device-data/[device]/backups/`

### Step 3: Test on Secondary AP
```bash
# For package updates:
./scripts/update_packages.sh secondary-ap

# For firmware updates via CLI:
ssh secondary-ap "owut upgrade"

# Or use LuCI web interface:
# Navigate to System > Attended Sysupgrade
```

### Step 4: Validation Testing
After updating secondary-ap:
- [ ] Verify WDS link active: `ssh secondary-ap "iw dev wl1-sta0 station dump | grep signal"`
- [ ] Test internet connectivity: `ssh secondary-ap "ping -c 3 8.8.8.8"`
- [ ] Check LuCI access: http://192.168.1.2/
- [ ] Monitor logs: `ssh upstairs "logread -f"` (watch for 5 minutes)
- [ ] Test WiFi client connections
- [ ] Verify all expected services running

### Step 5: Wait Period
- Package updates: Wait 1-2 hours
- Minor firmware: Wait 24 hours
- Major firmware: Wait 48-72 hours

### Step 6: Update Primary AP
If secondary-ap stable:
```bash
# Same commands but targeting primary-ap
./scripts/update_packages.sh primary-ap
```

### Step 7: Post-Update Verification
- [ ] Both routers accessible via SSH
- [ ] Internet connectivity working
- [ ] WDS link established
- [ ] DHCP functioning (check client devices)
- [ ] DNS resolving correctly
- [ ] No critical errors in logs

## Monthly Maintenance Routine

### Week 1: Update Check
```bash
./scripts/check_updates.sh
```
Review available updates and plan maintenance if needed.

### Week 2: Package Updates
Apply security patches and minor package updates:
```bash
./scripts/backup_all.sh
./scripts/update_packages.sh secondary-ap
# Wait 24 hours
./scripts/update_packages.sh primary-ap
```

### Week 3: Configuration Review
- Check disk space: `ssh [device] "df -h"`
- Review logs for issues: `ssh [device] "logread | grep -i error"`
- Verify WDS performance
- Clean old backups (keep last 3 months)

### Week 4: Documentation
- Update task logs in `private/device-data/[device]/task_log.md`
- Document any configuration changes
- Review and update this process document

## Attended Sysupgrade Tools

### Installation
Both routers have been configured with:
- `owut`: Command-line upgrade tool
- `luci-app-attendedsysupgrade`: Web interface for upgrades

### Using owut (CLI)
```bash
# Check for firmware updates
ssh [device] "owut check"

# Perform upgrade (preserves packages and config)
ssh [device] "owut upgrade"
```

### Using LuCI (Web)
1. Navigate to http://192.168.1.1/ or http://192.168.1.2/
2. Go to System > Attended Sysupgrade
3. Click "Check for Updates"
4. Review changes and click "Request Firmware"
5. Wait for build (2-10 minutes)
6. Apply upgrade

## Emergency Recovery Procedures

### If Router Becomes Inaccessible
1. Wait 5 minutes (may be rebooting)
2. Check physical connections and LEDs
3. Try failsafe mode (hold reset during boot)
4. Restore from backup if accessible
5. As last resort: TFTP recovery or serial console

### Backup Restoration
```bash
# Copy backup to router
scp private/device-data/[device]/backups/[latest_backup].tar.gz [device]:/tmp/

# Restore configuration
ssh [device] "sysupgrade -r /tmp/[latest_backup].tar.gz"
ssh [device] "reboot"
```

## Critical E8450 UBI Considerations

**WARNING**: The E8450 UBI variant has special requirements:
- **NEVER** use non-UBI firmware files
- **ALWAYS** use sysupgrade images (not factory)
- **NEVER** interrupt power during firmware updates
- **ALWAYS** use UPS during major upgrades if possible

## Script Descriptions

### check_updates.sh
- Checks both routers for available updates
- Shows package updates via opkg
- Shows firmware updates via owut
- Generates summary report

### backup_all.sh
- Creates timestamped configuration backups
- Backs up both routers sequentially
- Verifies backup file creation
- Maintains backup history

### update_packages.sh
- Updates package lists
- Shows available updates
- Applies updates with confirmation
- Restarts affected services
- Logs all actions

## Future Enhancements

### Ansible Automation (Planned)
Future implementation of Ansible for:
- Centralized configuration management
- Parallel updates across devices
- Automated health checks
- Configuration drift detection
- Compliance reporting

Implementation deferred until:
- Need for managing > 5 devices
- Requirement for complex configuration templates
- Need for automated compliance checking

### Monitoring Integration
Consider adding:
- Prometheus/Grafana for metrics
- Automated alerting for failures
- Performance trending
- Bandwidth monitoring

## Troubleshooting

### Common Issues

**Package update fails**
- Check internet connectivity
- Verify DNS resolution
- Check available disk space
- Try `opkg update` first

**WDS link drops after update**
- Restart wireless: `wifi reload`
- Check channel settings match
- Verify WDS enabled in config

**LuCI not accessible**
- Restart uhttpd: `/etc/init.d/uhttpd restart`
- Check firewall rules
- Verify listening on port 80/443

**High memory usage**
- Normal after updates (package cache)
- Clear with: `sync && echo 3 > /proc/sys/vm/drop_caches`

## Version History

- 2025-01-09: Initial documentation created
- 2025-01-09: Installed Attended Sysupgrade tools
- 2025-01-09: Created update management scripts

## Resources

- [OpenWrt E8450 Device Page](https://openwrt.org/toh/linksys/e8450)
- [Attended Sysupgrade Documentation](https://openwrt.org/docs/guide-user/installation/attended.sysupgrade)
- [OpenWrt Security Advisories](https://openwrt.org/advisory/start)
- [E8450 UBI Installer](https://github.com/dangowrt/owrt-ubi-installer)