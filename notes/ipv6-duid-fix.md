# IPv6 Prefix Delegation and the DUID Problem

## Background: What is a DUID?

A DUID (DHCPv6 Unique Identifier) is a client identifier used in DHCPv6 to distinguish devices requesting addresses and prefixes. Unlike DHCPv4 which uses MAC addresses to identify clients, DHCPv6 uses DUIDs because a single device may have multiple interfaces with different MACs but should present a consistent identity to the server.

There are four DUID types defined in RFC 8415:

| Type | Code | Format | Notes |
|------|------|--------|-------|
| DUID-LLT | 0001 | hardware type + timestamp + MAC | Most common on Linux/ISP routers. Timestamp is seconds since 2000-01-01. |
| DUID-EN | 0002 | enterprise number + identifier | Vendor-specific. |
| DUID-LL | 0003 | hardware type + MAC | Deterministic, no timestamp. Common on ISP-supplied CPE. |
| DUID-UUID | 0004 | UUID | Used by OpenWrt by default. Generated once and stored in UCI config. |

The hardware type field is `0001` for Ethernet.

## The Problem: OpenWrt 25.12 Changes the DUID Format

OpenWrt 25.12 introduced a breaking change to DUID generation (October 2025 commit).
Previously, odhcp6c generated a DUID-LL (type 3) at runtime from each interface's MAC
address. No DUID was stored in the config. Starting with 25.12, a first-boot script
generates a DUID-UUID (type 4) and stores it in `network.globals.dhcp_default_duid`.

This means upgrading from 24.10 to 25.12 silently changes the DUID your router presents
to the ISP's DHCPv6 server. If the BNG has the old DUID-LL on file and validates PD
requests against it, prefix delegation breaks while basic address assignment (IA_NA)
may still work since it can fall back to MAC-based identification or SLAAC.

The symptom: DHCPv6 SOLICIT messages go out with IA_PD, the BNG responds with IA_NA
(address + DNS) but ignores the prefix request entirely. Testing different reqprefix
hints (/48, /56, /60, auto) and PD-only mode makes no difference because the issue is
identity, not the request parameters.

We confirmed this by checking pre-upgrade backups from 24.10.6: `config globals 'globals'`
had no `dhcp_default_duid` option at all. After the 25.12 upgrade, a UUID-based DUID
appeared. Swapping in the original ISP-supplied router (which uses DUID-LL) restored
PD immediately.

## Why BNGs Care About DUIDs

The BNG (Broadband Network Gateway) maintains a lease database indexed by DUID. When it
delegates a prefix via IA_PD, it installs routing entries pointing that prefix at the
customer's connection. This is a heavier commitment than IA_NA (a single address), so
some BNGs validate the client identity more strictly for PD than for address assignment.

If you present a DUID the BNG doesn't recognise, it may serve IA_NA (safe, single address)
but refuse IA_PD (risky, installs routes for an entire prefix block). This is what happened
after the 25.12 upgrade.

## The Fix

Set OpenWrt's DUID to match the original CPE's DUID-LL format:

```
uci set network.globals.dhcp_default_duid=00030001[wan mac without colons]
```

For a WAN MAC of `AA:BB:CC:DD:EE:FF`:

```
uci set network.globals.dhcp_default_duid=00030001aabbccddeeff
uci commit network
service network restart
```

DUID-LL is deterministic (derived from MAC alone, no timestamp), so it's reproducible and stable across reboots and firmware upgrades. If you know the WAN MAC of the ISP's original router, you can always reconstruct the DUID-LL.

## Diagnostic Approach

If you suspect a DUID mismatch:

1. Capture DHCPv6 on the WAN: `tcpdump -i wan -n -v "udp port 546 or udp port 547"`
2. Check if the BNG responds to SOLICIT at all (look for ADVERTISE packets)
3. If IA_NA works but IA_PD doesn't, the DUID is the likely culprit
4. Swap in the original ISP router to confirm PD works with its DUID
5. Clone the DUID format onto your router

## IPv6 Masquerade for Tailscale Exit Node

Separately from PD, Tailscale exit node IPv6 traffic requires masquerade (NAT66) on the tailscale firewall zone. Without it, outbound traffic from the Tailscale ULA source (fd7a:...) gets dropped by the ISP since it's not globally routable.

```
uci set firewall.@zone[2].masq6=1
uci commit firewall
service firewall restart
```

This only affects traffic originating from the tailscale0 interface being forwarded to WAN. Normal LAN→WAN IPv6 traffic is unaffected.
