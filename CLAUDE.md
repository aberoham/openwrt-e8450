# Claude Code Context

OpenWrt fleet management for Linksys E8450 (UBI) routers.

## Key Files

- `README.md` - Main documentation, network architecture, commands
- `notes/UPGRADE_PROCESS.md` - Update procedures and maintenance routines
- `notes/flash-layout-v2-upgrade.md` - Flash layout migration guide
- `scripts/` - Backup and update automation

## Device Access

- SSH: `root@192.168.1.1` (primary-ap), `root@192.168.1.2` (secondary-ap)
- Web: http://192.168.1.1 (LuCI)

## Critical Notes

- E8450 UBI requires UBI-specific firmware only
- Flash layout v1.0 devices must migrate to v2.0 before upgrading to 24.10.5+
- Always backup before changes: `sysupgrade -b /tmp/backup.tar.gz`
