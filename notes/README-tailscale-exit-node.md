# Tailscale Pure Exit Node Setup for OpenWrt E8450

## Overview

This guide configures Tailscale on the primary-ap OpenWrt router as a **pure exit node** - providing internet access through your residential ISP without exposing any local network resources.

### What This Setup Provides
- ✅ Route internet traffic through home ISP (IPv4 and IPv6)
- ✅ Access websites as if browsing from home
- ✅ Complete isolation between Tailscale and LAN
- ✅ No corporate traffic on home network
- ✅ No home network access from Tailscale

### What This Setup Does NOT Provide
- ❌ No access to local network devices
- ❌ No subnet routing to 192.168.1.0/24
- ❌ No remote router management via Tailscale
- ❌ No cross-network pollution

## Prerequisites

### System Requirements
- **Architecture**: ARMv8 (ARM64) ✓
- **Memory**: 500MB RAM (50-70MB used by Tailscale) ✓
- **Storage**: 76MB available (15MB needed) ✓
- **OpenWrt**: 24.10.2 ✓
- **Package**: tailscale 1.80.3-r1 ✓

### Network Configuration
- **LAN**: 192.168.1.0/24
- **Router IP**: 192.168.1.1
- **ISP**: IPv6 native with IPv4

## Installation Steps

### 1. Create Backup

```bash
./scripts/backup_all.sh
```

### 2. Install Tailscale

```bash
ssh primary-ap "opkg update && opkg install tailscale"
```

### 3. Enable IP Forwarding

Enable both IPv4 and IPv6 forwarding for exit node functionality:

```bash
ssh primary-ap "cat >> /etc/sysctl.conf << 'EOF'
# Tailscale exit node forwarding
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF"

ssh primary-ap "sysctl -p"
```

### 4. Configure Firewall Isolation

Create an isolated Tailscale zone that can ONLY forward to WAN:

```bash
ssh primary-ap "cat >> /etc/config/firewall << 'EOF'

# Tailscale isolated zone
config zone
    option name 'tailscale'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option masq '1'
    option family 'any'
    list device 'tailscale0'

# Allow Tailscale to WAN only (no LAN access)
config forwarding
    option src 'tailscale'
    option dest 'wan'
    option family 'any'
EOF"

# Reload firewall
ssh primary-ap "/etc/init.d/firewall reload"
```

### 5. Start Tailscale Service

```bash
ssh primary-ap "/etc/init.d/tailscale enable"
ssh primary-ap "/etc/init.d/tailscale start"
```

### 6. Configure as Pure Exit Node

**Important**: Do NOT use `--advertise-routes` to prevent LAN access:

```bash
ssh primary-ap "tailscale up --advertise-exit-node"
```

This command will output an authentication URL. Visit it to authorize the device.

### 7. Enable Exit Node in Admin Console

1. Log into [admin.tailscale.com](https://admin.tailscale.com)
2. Navigate to Machines
3. Find your "primary-ap" device
4. Click the three dots menu → Edit Route Settings
5. Enable "Use as exit node"
6. **Do NOT enable any subnet routes**

### 8. Verify Firewall Rules

Ensure Tailscale cannot access LAN:

```bash
# Check firewall zones
ssh primary-ap "uci show firewall | grep tailscale"

# Verify no LAN forwarding exists
ssh primary-ap "uci show firewall | grep forwarding" | grep -v "dest='wan'"
```

## Testing

### From Work Device

1. Connect to Tailscale
2. Select downstairs router as exit node
3. Run tests:

```bash
# Test IPv4 exit node
curl -4 ifconfig.me
# Should show home IPv4 address

# Test IPv6 exit node  
curl -6 ifconfig.me
# Should show home IPv6 address

# Verify NO LAN access
ping 192.168.1.1
# Should fail - no route to host

# Test internet browsing
curl -I https://www.google.com
# Should work normally
```

### From Router

Check Tailscale status:

```bash
ssh primary-ap "tailscale status"
ssh primary-ap "tailscale ip -4"
ssh primary-ap "tailscale ip -6"
```

Monitor resource usage:

```bash
ssh primary-ap "ps | grep tailscale"
ssh primary-ap "free -m"
```

## Security Considerations

### Network Isolation
- Tailscale zone explicitly blocked from LAN zone
- Only WAN forwarding permitted
- No advertised routes to local network
- Reject policy on Tailscale input

### Best Practices
1. Regularly update Tailscale package
2. Monitor logs for unauthorized access attempts
3. Review firewall rules after OpenWrt updates
4. Keep exit node disabled when not in use

## Troubleshooting

### Exit Node Not Working

```bash
# Check if IP forwarding is enabled
ssh primary-ap "sysctl net.ipv4.ip_forward"
ssh primary-ap "sysctl net.ipv6.conf.all.forwarding"

# Verify Tailscale is running
ssh primary-ap "/etc/init.d/tailscale status"

# Check firewall zones
ssh primary-ap "fw3 print"
```

### IPv6 Not Working

```bash
# Check IPv6 connectivity
ssh primary-ap "ping6 -c 1 google.com"

# Verify IPv6 forwarding
ssh primary-ap "cat /proc/sys/net/ipv6/conf/all/forwarding"
```

### High Memory Usage

If Tailscale uses too much memory:

```bash
# Install zram-swap for memory compression
ssh primary-ap "opkg install zram-swap"
ssh primary-ap "/etc/init.d/zram enable"
ssh primary-ap "/etc/init.d/zram start"
```

### Complete Removal

To completely remove Tailscale:

```bash
ssh primary-ap "tailscale down"
ssh primary-ap "/etc/init.d/tailscale stop"
ssh primary-ap "/etc/init.d/tailscale disable"
ssh primary-ap "opkg remove tailscale"

# Remove firewall rules
ssh primary-ap "uci delete firewall.@zone[-1]"  # Remove tailscale zone
ssh primary-ap "uci delete firewall.@forwarding[-1]"  # Remove forwarding rule
ssh primary-ap "uci commit firewall"
ssh primary-ap "/etc/init.d/firewall reload"
```

## Maintenance

### Update Tailscale

```bash
ssh primary-ap "opkg update && opkg upgrade tailscale"
```

### Monitor Logs

```bash
# Tailscale logs
ssh primary-ap "logread | grep tailscale"

# Firewall logs
ssh primary-ap "logread | grep firewall"
```

### Check Connection Status

```bash
ssh primary-ap "tailscale status"
ssh primary-ap "tailscale netcheck"
```

## Additional Notes

- Exit node performance depends on home internet upload speed
- Tailscale uses ~50-70MB RAM on average
- No configuration files need backing up (auth state in /var/lib/tailscale)
- Service automatically starts on router reboot