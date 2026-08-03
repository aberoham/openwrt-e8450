# Tailscale Exit Node DNS and IPv6 Fix

Date: 2026-04-03
Router: downstairs (OpenWrt 25.12.2, Tailscale 1.94.1)

## Symptoms

- Tailscale exit node appeared connected and routing IPv4 traffic
- DNS resolution failed on devices using the exit node (e.g., iPhone on 5G)
- `tailscale status` showed health warning: "Tailscale can't reach the configured DNS servers"
- IPv6 connectivity through the exit node didn't work at all

## Root Cause 1: Empty `/etc/resolv.conf` (DNS failure)

### How Tailscale exit node DNS works

Exit node DNS does **not** flow as raw IP packets through the WireGuard tunnel.
The actual mechanism is:

1. Client sends DNS to `100.100.100.100` (Quad100, Tailscale's local stub resolver)
2. Client's Tailscale forwards non-MagicDNS queries to the exit node via a
   **PeerAPI HTTP endpoint** (`/dns-query`) over the tunnel
3. Exit node's `HandlePeerDNSQuery()` reads `/etc/resolv.conf` to find upstream DNS
4. It queries that nameserver **as a local process** (source IP = `127.0.0.1`)
5. Response flows back through the PeerAPI channel

### What went wrong

On OpenWrt, `/etc/resolv.conf` should be a symlink to `/tmp/resolv.conf` (which
contains `nameserver 127.0.0.1` pointing to dnsmasq). Instead, it was a **0-byte
regular file** on the overlay filesystem.

This happened because Tailscale's `directManager` (the DNS manager for Linux
systems without systemd-resolved) has no OpenWrt awareness. When Tailscale was
first configured with `accept-dns=true`:

1. `directManager` renamed the symlink `/etc/resolv.conf → /tmp/resolv.conf`
   to a backup file (`/etc/resolv.pre-tailscale-backup.conf`)
2. Wrote a new regular file at `/etc/resolv.conf` containing `nameserver 100.100.100.100`
3. This regular file landed on the overlay filesystem, masking the squashfs original

When `accept-dns` was later set to `false`, Tailscale tried to restore the backup.
But the backup was lost during the 24.10→25.12 sysupgrade (overlay wipe). The
restore failed silently, leaving a 0-byte file.

With `/etc/resolv.conf` empty, `HandlePeerDNSQuery()` found no nameservers and
returned SERVFAIL to all client DNS queries.

### The fix

```sh
# Remove the empty overlay file and recreate the symlink
rm /etc/resolv.conf
ln -sf /tmp/resolv.conf /etc/resolv.conf
/etc/init.d/tailscale restart
```

On OpenWrt with overlayfs, `rm` should reveal the underlying squashfs symlink.
If the whiteout prevents that (as happened here), recreate the symlink manually.

### Why `accept-dns=false` is correct

The `accept-dns` (CorpDNS) setting controls whether Tailscale modifies the
**exit node's own** DNS configuration. It has no effect on the PeerAPI DNS
handler that serves exit node clients. The handler reads `/etc/resolv.conf`
directly, regardless of this setting.

Leaving `accept-dns=false` prevents Tailscale from clobbering `/etc/resolv.conf`
again in the future.

### Why dnsmasq's `localservice=1` is not a problem

The PeerAPI handler queries DNS from the `tailscaled` process on localhost
(source IP `127.0.0.1`), not from the tailscale0 interface. dnsmasq's
`localservice` restriction only checks the source subnet — localhost always
passes. No dnsmasq configuration change is needed.

### Related Tailscale issues

- [#15174](https://github.com/tailscale/tailscale/issues/15174) — Tailscale 1.80.2 breaks DNS on OpenWrt
- [#18513](https://github.com/tailscale/tailscale/issues/18513) — direct DNS manager settings not applied on restart

## Root Cause 2: Source-constrained IPv6 default routes (IPv6 failure)

### The problem

OpenWrt's DHCPv6 client (odhcp6c) creates **source-constrained** default routes:

```
default from 2a10:xxxx:xxxx::/48 via fe80::... dev wan metric 512
default from 2a10:xxxx:x:xxxx::/64 via fe80::... dev wan metric 512
```

These routes only match packets whose source address falls within the specified
prefix. Tailscale exit node traffic has source addresses in the `fd7a:115c:a1e0::/48`
ULA range (Tailscale's address space), which matches neither prefix.

Result: IPv6 packets from tailscale0 hit no default route → dropped at the
routing stage → never reach the forward chain (confirmed by zero packet counters
on all ip6 filter ts-forward rules).

Note: IPv4 works because the IPv4 default route has no source constraint.

### Why NAT66 masquerade already exists but wasn't triggered

Tailscale's nftables rules include IPv6 masquerade in `ip6 nat ts-postrouting`
for packets marked by `ts-forward`. The OpenWrt fw4 tailscale zone also has
`masq6='1'`. But masquerade happens at POSTROUTING — after the routing decision.
Since the routing decision failed (no matching route), packets were dropped
before reaching the NAT stage.

### The fix

Add a separate routing table with an unrestricted default route, scoped to
traffic from tailscale0 only:

```sh
# One-time (immediate effect)
ip -6 route add default via <gateway> dev wan table 100
ip -6 rule add iif tailscale0 lookup 100 priority 5269
```

For persistence, a hotplug script at `/etc/hotplug.d/iface/99-tailscale-ipv6`
re-creates the route whenever the WAN interface comes up, dynamically discovering
the current IPv6 gateway address. Added to `/etc/sysupgrade.conf` for firmware
upgrade persistence.

### Security considerations

- The routing rule is scoped to `iif tailscale0` — only packets arriving on the
  Tailscale interface use table 100. WAN-sourced traffic cannot trigger this rule.
- Tailscale controls what gets delivered to tailscale0 (only authenticated peers).
- The WAN zone remains `input=REJECT, forward=REJECT` — no new services exposed.
- dnsmasq is not bound to any WAN address — no open resolver risk.
- The IPv6 masquerade rewrites Tailscale ULA sources to the WAN's public address
  before packets leave the router, so ULA addresses never leak to the ISP.

## Files changed on the router

| File | Change |
|------|--------|
| `/etc/resolv.conf` | Restored symlink → `/tmp/resolv.conf` |
| `/etc/hotplug.d/iface/99-tailscale-ipv6` | New hotplug script for IPv6 routing |
| `/etc/sysupgrade.conf` | Added hotplug script path for persistence |

## Verification

```sh
# DNS: Tailscale should find system nameservers
tailscale dns status  # System DNS section should show 127.0.0.1

# DNS: Health warning should be gone
tailscale status  # No "can't reach DNS" warning

# IPv6: Routing rule in place
ip -6 rule show | grep tailscale  # Should show table 100 rule
ip -6 route show table 100       # Should show default route

# Test from a remote device using the exit node:
curl -4 ifconfig.me   # Should show home IPv4
curl -6 ifconfig.me   # Should show home IPv6
```
