# Claude Code Context

OpenWrt fleet management for Linksys E8450 (UBI) routers.

## Important: Public Repository

This is an open public repository. **Never commit private deployment details:**
- No real IP addresses (use examples like 192.168.1.x or 10.x.x.x)
- No hostnames, MAC addresses, or device identifiers
- No Tailscale auth keys or tokens
- No SSH keys or credentials
- Private data belongs in `private/` directory (symlinked to separate private repo)
- **Claude Code**: Check `private/device-data/accesspoints.conf` for actual device IPs and configuration

## Key Files

- `README.md` - Main documentation, network architecture, commands
- `notes/UPGRADE_PROCESS.md` - Update procedures and maintenance routines
- `notes/flash-layout-v2-upgrade.md` - Flash layout migration guide
- `notes/tailscale-setup.md` - Tailscale exit node and subnet routing setup
- `scripts/deploy_tailscale.sh` - Automated Tailscale deployment with firewall config
- `scripts/remove_tailscale.sh` - Clean Tailscale removal
- `scripts/` - Backup and update automation

## Device Access

- SSH: `root@192.168.1.1` (primary-ap), `root@192.168.1.2` (secondary-ap)
- Web: http://192.168.1.1 (LuCI)

## Tailscale Configuration

When Tailscale is deployed, the firewall includes a `tailscale` zone with:
- Forwarding to WAN (exit node functionality)
- Forwarding to/from LAN (subnet routing)
- Masquerade enabled for NAT

## Firewall Security Notes

Default hardening applied:
- SSH bound to LAN interface only (not accessible from WAN)
- Unused IPSec/ISAKMP rules removed
- Web UI protected by firewall + rfc1918_filter
- WAN zone: `input=REJECT`, `forward=REJECT`

## Critical Notes

- E8450 UBI requires UBI-specific firmware only
- Flash layout v1.0 devices must migrate to v2.0 before upgrading to 24.10.5+
- Always backup before changes: `sysupgrade -b /tmp/backup.tar.gz`
