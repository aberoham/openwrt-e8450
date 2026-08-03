#!/bin/bash
# test_wan_exposure.sh - Test firewall exposure from external host
# Run this from a dedicated server OUTSIDE your network
#
# Usage: ./test_wan_exposure.sh <wan-ipv4> <wan-ipv6>

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <wan-ipv4> <wan-ipv6>"
    echo "Example: $0 203.0.113.1 2001:db8::1"
    exit 1
fi

IPV4="$1"
IPV6="$2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=============================================="
echo "OpenWrt WAN Exposure Test"
echo "Target IPv4: $IPV4"
echo "Target IPv6: $IPV6"
echo "=============================================="
echo ""

# Check for required tools
for cmd in nmap dig curl nc ping; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}Missing required tool: $cmd${NC}"
        exit 1
    fi
done

echo "=== 1. TCP Port Scan (IPv4) ==="
echo "Ports: 22 (SSH), 53 (DNS), 80 (HTTP), 443 (HTTPS), 8080"
nmap -Pn -sT -p 22,53,80,443,8080 --open "$IPV4" || true
echo ""

echo "=== 2. TCP Port Scan (IPv6) ==="
nmap -6 -Pn -sT -p 22,53,80,443,8080 --open "$IPV6" || true
echo ""

echo "=== 3. UDP Port Scan (IPv4) ==="
echo "Ports: 53 (DNS), 67-68 (DHCP), 546-547 (DHCPv6), 41641 (Tailscale)"
echo "(UDP scans are slow, please wait...)"
sudo nmap -Pn -sU -p 53,67,68,546,547,41641 "$IPV4" || true
echo ""

echo "=== 4. UDP Port Scan (IPv6) ==="
sudo nmap -6 -Pn -sU -p 53,546,547,41641 "$IPV6" || true
echo ""

echo "=== 5. DNS Query Test (IPv4) ==="
echo "Attempting DNS lookup via $IPV4..."
if dig @"$IPV4" google.com +timeout=3 +tries=1 +short 2>/dev/null | grep -q .; then
    echo -e "${RED}FAIL: DNS responded - resolver is exposed!${NC}"
else
    echo -e "${GREEN}PASS: DNS query failed/timed out (expected)${NC}"
fi
echo ""

echo "=== 6. DNS Query Test (IPv6) ==="
echo "Attempting DNS lookup via $IPV6..."
if dig @"$IPV6" google.com +timeout=3 +tries=1 +short 2>/dev/null | grep -q .; then
    echo -e "${RED}FAIL: DNS responded - resolver is exposed!${NC}"
else
    echo -e "${GREEN}PASS: DNS query failed/timed out (expected)${NC}"
fi
echo ""

echo "=== 7. HTTP Test (IPv4) ==="
echo "Attempting HTTP connection to $IPV4:80..."
if curl -s --connect-timeout 5 "http://$IPV4/" &>/dev/null; then
    echo -e "${RED}FAIL: HTTP responded - web UI is exposed!${NC}"
else
    echo -e "${GREEN}PASS: HTTP connection failed (expected)${NC}"
fi
echo ""

echo "=== 8. HTTP Test (IPv6) ==="
echo "Attempting HTTP connection to [$IPV6]:80..."
if curl -s --connect-timeout 5 "http://[$IPV6]/" &>/dev/null; then
    echo -e "${RED}FAIL: HTTP responded - web UI is exposed!${NC}"
else
    echo -e "${GREEN}PASS: HTTP connection failed (expected)${NC}"
fi
echo ""

echo "=== 9. HTTPS Test (IPv4) ==="
echo "Attempting HTTPS connection to $IPV4:443..."
if curl -sk --connect-timeout 5 "https://$IPV4/" &>/dev/null; then
    echo -e "${RED}FAIL: HTTPS responded - web UI is exposed!${NC}"
else
    echo -e "${GREEN}PASS: HTTPS connection failed (expected)${NC}"
fi
echo ""

echo "=== 10. SSH Test (IPv4) ==="
echo "Attempting SSH connection to $IPV4:22..."
if nc -zw3 "$IPV4" 22 2>/dev/null; then
    echo -e "${RED}FAIL: SSH port is open!${NC}"
else
    echo -e "${GREEN}PASS: SSH connection failed (expected)${NC}"
fi
echo ""

echo "=== 11. SSH Test (IPv6) ==="
echo "Attempting SSH connection to [$IPV6]:22..."
if nc -zw3 "$IPV6" 22 2>/dev/null; then
    echo -e "${RED}FAIL: SSH port is open!${NC}"
else
    echo -e "${GREEN}PASS: SSH connection failed (expected)${NC}"
fi
echo ""

echo "=== 12. ICMP Ping Test (IPv4) ==="
if ping -c 2 -W 3 "$IPV4" &>/dev/null; then
    echo -e "${YELLOW}INFO: Ping responds (currently allowed by firewall)${NC}"
else
    echo -e "${GREEN}Ping blocked${NC}"
fi
echo ""

echo "=== 13. ICMP Ping Test (IPv6) ==="
if ping -c 2 -W 3 "$IPV6" &>/dev/null; then
    echo -e "${YELLOW}INFO: Ping responds (currently allowed by firewall)${NC}"
else
    echo -e "${GREEN}Ping blocked${NC}"
fi
echo ""

echo "=============================================="
echo "Summary:"
echo "- TCP 22,53,80,443: should be filtered/closed"
echo "- UDP 53: should be filtered/no response"
echo "- UDP 41641: OPEN is OK (Tailscale WireGuard)"
echo "- ICMP ping: responding is OK (optional to disable)"
echo "=============================================="
