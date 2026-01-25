# Tailscale Setup for OpenWrt E8450

This guide configures Tailscale on OpenWrt routers with both **exit node** and **subnet routing** capabilities, allowing you to:
- Route internet traffic through your home connection from anywhere
- Access local network devices (printers, NAS, router admin) remotely

## Prerequisites

### System Requirements
- OpenWrt 22.03+ (uses nftables by default)
- ~15MB storage for Tailscale package
- ~50-70MB RAM during operation
- Internet connectivity for initial setup

### Network Understanding
Before proceeding, identify your:
- **LAN subnet**: e.g., `192.168.1.0/24`
- **Router LAN IP**: e.g., `192.168.1.1`
- **Desired hostname**: How the router will appear in Tailscale

## Quick Start

### Deploy Tailscale

```bash
# List available routers
./scripts/deploy_tailscale.sh --list

# Deploy to a specific router
./scripts/deploy_tailscale.sh <router_name>
```

The script will:
1. Create a pre-deployment backup
2. Install Tailscale via opkg
3. Configure nftables firewall mode
4. Enable IP forwarding (IPv4 and IPv6)
5. Create firewall zone with LAN and WAN access
6. Configure state persistence across sysupgrade
7. Start the Tailscale service

### Complete Authentication

After deployment, SSH to the router and run:

```bash
tailscale up --advertise-exit-node --advertise-routes=192.168.1.0/24 --hostname=my-router
```

This outputs an authentication URL. Visit it to authorize the device.

### Enable in Admin Console

1. Go to [admin.tailscale.com](https://admin.tailscale.com)
2. Find your router in the Machines list
3. Click the menu (...) and select "Edit route settings"
4. Enable "Use as exit node"
5. Approve the advertised subnet route

## What Gets Configured

### Firewall Zone (via UCI)

```
Zone: tailscale
  - Input: ACCEPT
  - Output: ACCEPT
  - Forward: REJECT
  - Masquerade: enabled
  - Device: tailscale0
```

### Forwarding Rules

| Source | Destination | Purpose |
|--------|-------------|---------|
| tailscale | wan | Exit node (internet access) |
| tailscale | lan | Subnet routing (local devices) |
| lan | tailscale | Return traffic |

### Persistence

These paths are added to `/etc/sysupgrade.conf`:
- `/etc/config/tailscale` - Configuration
- `/var/lib/tailscale/` - Auth state and keys

## Verification

### Check Service Status

```bash
ssh <router> "tailscale status"
ssh <router> "tailscale ip -4"
```

### Verify nftables Mode (Critical)

```bash
ssh <router> "uci get tailscale.config.fw_mode"
# Should return: nftables
```

### Verify Firewall Rules

```bash
ssh <router> "uci show firewall | grep tailscale"
```

### Test Exit Node

From a remote device connected to Tailscale:
```bash
# Select the router as exit node in Tailscale client
curl -4 ifconfig.me
# Should show your home IP address
```

### Test Subnet Routing

From a remote device connected to Tailscale:
```bash
ping 192.168.1.1      # Router
ping 192.168.1.x      # Other LAN devices
```

## Troubleshooting

### "iptables not found" Error

**Symptom**: Installation fails with iptables dependency error.

**Cause**: Package expects iptables but OpenWrt uses nftables.

**Solution**: The official OpenWrt Tailscale package (v1.80+) defaults to nftables. If you encounter this error:

1. Ensure you're using the official package:
   ```bash
   opkg update && opkg install tailscale
   ```

2. If still failing, manually set nftables mode:
   ```bash
   uci set tailscale.config=tailscale
   uci set tailscale.config.fw_mode='nftables'
   uci commit tailscale
   ```

3. Alternative: Use [GuNanOvO's package feed](https://gunanovo.github.io/openwrt-tailscale/) which provides pre-built nftables-compatible binaries.

### Exit Node Not Working

1. Check IP forwarding:
   ```bash
   sysctl net.ipv4.ip_forward
   sysctl net.ipv6.conf.all.forwarding
   # Both should return 1
   ```

2. Verify exit node is enabled in Tailscale admin console.

3. Check firewall forwarding:
   ```bash
   uci show firewall | grep -A2 "tailscale.*wan"
   ```

### Subnet Routing Not Working

1. Verify route is approved in Tailscale admin console.

2. Check firewall forwarding to LAN:
   ```bash
   uci show firewall | grep -A2 "tailscale.*lan"
   ```

3. Ensure return traffic rule exists:
   ```bash
   uci show firewall | grep -A2 "lan.*tailscale"
   ```

### Connection Issues After Reboot

1. Check service is enabled:
   ```bash
   /etc/init.d/tailscale enabled && echo "Enabled" || echo "Disabled"
   ```

2. Check state directory exists:
   ```bash
   ls -la /var/lib/tailscale/
   ```

3. Verify sysupgrade persistence:
   ```bash
   grep tailscale /etc/sysupgrade.conf
   ```

### High Memory Usage

If Tailscale uses too much memory:

```bash
# Install zram-swap for memory compression
opkg install zram-swap
/etc/init.d/zram enable
/etc/init.d/zram start
```

## Exit Node vs Subnet Router

| Feature | Exit Node | Subnet Router |
|---------|-----------|---------------|
| Internet traffic | Routes through home ISP | No change |
| Access home LAN | No | Yes |
| Use case | Browse as if at home | Access printer, NAS, etc. |
| Tailscale flag | `--advertise-exit-node` | `--advertise-routes=x.x.x.x/xx` |

You can enable **both** simultaneously (as this setup does).

## Removal

To completely remove Tailscale:

```bash
./scripts/remove_tailscale.sh <router_name>
```

This will:
- Stop and disable the service
- Remove the Tailscale package
- Delete firewall zone and forwarding rules
- Clean up state directory
- Remove sysupgrade.conf entries

**Note**: The device will remain in your Tailscale admin console. Delete it manually at admin.tailscale.com.

## Package Sources

### Official OpenWrt Package (Recommended)

- **Install**: `opkg install tailscale`
- **Update**: `opkg upgrade tailscale`
- **Pros**: Standard package management, tested with OpenWrt
- **Cons**: May lag behind upstream releases

### GuNanOvO's Package Feed (Alternative)

- **URL**: https://gunanovo.github.io/openwrt-tailscale/
- **Pros**: Latest versions, UPX compressed (smaller binary)
- **Cons**: Third-party source

To use GuNanOvO's feed:
```bash
# Add feed (check website for current instructions)
echo "src/gz tailscale https://gunanovo.github.io/openwrt-tailscale/packages/aarch64_cortex-a53" >> /etc/opkg/customfeeds.conf
opkg update
opkg install tailscale
```

## Security Considerations

### Firewall Design

The default configuration allows Tailscale to access both LAN and WAN:
- **LAN access**: Required for subnet routing to local devices
- **WAN access**: Required for exit node functionality

For a **pure exit node** (no LAN access), modify the firewall:
```bash
# Remove tailscale -> lan forwarding
uci show firewall | grep -n "tailscale.*lan"
# Delete the appropriate forwarding rule
```

### Access Controls

Use Tailscale ACLs (Access Control Lists) to restrict:
- Which devices can use the exit node
- Which devices can access subnet routes
- Which users can connect to specific machines

Configure ACLs at: https://login.tailscale.com/admin/acls

## References

- [Tailscale Subnet Routers](https://tailscale.com/kb/1019/subnets)
- [Tailscale Exit Nodes](https://tailscale.com/kb/1103/exit-nodes)
- [Tailscale Firewall Mode](https://tailscale.com/kb/1294/firewall-mode)
- [OpenWrt Tailscale Package](https://github.com/openwrt/packages/tree/master/net/tailscale)
