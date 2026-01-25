#!/bin/bash

# deploy_tailscale.sh - Deploy Tailscale to an OpenWrt router
# Usage: ./deploy_tailscale.sh <router_name>
#        ./deploy_tailscale.sh --list    # List configured routers
#
# Installs Tailscale via opkg, configures firewall for exit node and subnet routing,
# and persists state across sysupgrade. After deployment, run `tailscale up` manually.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory (parent of scripts directory)
BASE_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"

# Load access point configuration
source "${BASE_DIR}/scripts/lib/ap_functions.sh"
check_ap_config

# Print header
print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Tailscale Deployment for OpenWrt - $(date +%Y-%m-%d)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
}

# Print usage
print_usage() {
    echo "Usage: $0 <router_name>"
    echo "       $0 --list     List configured routers"
    echo
    echo "This script deploys Tailscale to an OpenWrt router with:"
    echo "  - Exit node capability (route internet through home)"
    echo "  - Subnet routing support (access LAN devices remotely)"
    echo "  - Firewall configuration via UCI"
    echo "  - State persistence across sysupgrade"
    echo
    echo "After deployment, complete setup with:"
    echo "  ssh <router> \"tailscale up --advertise-exit-node --advertise-routes=<LAN_SUBNET>\""
}

# Create pre-deployment backup
create_backup() {
    local router=$1
    local ssh_cmd=$(get_ap_ssh "$router")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${BASE_DIR}/private/device-data/${router}/backups"
    local backup_file="${backup_dir}/pre-tailscale_${timestamp}.tar.gz"

    echo -e "${YELLOW}Creating pre-deployment backup...${NC}"
    mkdir -p "$backup_dir"

    if $ssh_cmd "sysupgrade -b /tmp/backup_temp.tar.gz" 2>/dev/null; then
        if $ssh_cmd "cat /tmp/backup_temp.tar.gz" > "$backup_file" 2>/dev/null; then
            $ssh_cmd "rm -f /tmp/backup_temp.tar.gz" 2>/dev/null
            local size=$(ls -lh "$backup_file" 2>/dev/null | awk '{print $5}')
            echo -e "  ${GREEN}[OK] Backup created: $(basename "$backup_file") ($size)${NC}"
            return 0
        fi
    fi

    echo -e "  ${RED}[WARN] Backup failed - continuing anyway${NC}"
    return 1
}

# Check if Tailscale is already installed
check_existing() {
    local ssh_cmd=$1

    if $ssh_cmd "opkg list-installed | grep -q tailscale" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Install Tailscale package
install_tailscale() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Installing Tailscale...${NC}"

    # Update package lists
    echo "  Updating package lists..."
    local update_output
    if ! update_output=$($ssh_cmd "opkg update" 2>&1); then
        echo -e "  ${RED}[FAIL] Failed to update package lists${NC}"
        echo "$update_output" | grep -v "^Downloading\|^Updated\|^Signature" || true
        return 1
    fi
    echo -e "  ${GREEN}[OK] Package lists updated${NC}"

    # Install tailscale
    echo "  Installing tailscale package..."
    local install_output
    if install_output=$($ssh_cmd "opkg install tailscale" 2>&1); then
        echo -e "  ${GREEN}[OK] Tailscale installed${NC}"
    else
        echo -e "  ${RED}[FAIL] Failed to install Tailscale${NC}"
        echo "$install_output"
        echo
        echo -e "${YELLOW}If you see iptables errors, the official package may need updating.${NC}"
        echo "Consider using GuNanOvO's optimized package feed:"
        echo "  https://gunanovo.github.io/openwrt-tailscale/"
        return 1
    fi

    return 0
}

# Verify nftables mode
verify_nftables() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Verifying firewall mode...${NC}"

    local fw_mode=$($ssh_cmd "uci get tailscale.config.fw_mode 2>/dev/null || echo 'not_set'")

    if [ "$fw_mode" = "nftables" ]; then
        echo -e "  ${GREEN}[OK] Using nftables mode${NC}"
        return 0
    elif [ "$fw_mode" = "not_set" ]; then
        # Set nftables mode explicitly
        echo "  Setting nftables mode..."
        $ssh_cmd "uci set tailscale.config=tailscale"
        $ssh_cmd "uci set tailscale.config.fw_mode='nftables'"
        $ssh_cmd "uci commit tailscale"
        echo -e "  ${GREEN}[OK] Configured for nftables${NC}"
        return 0
    else
        echo -e "  ${YELLOW}[WARN] Firewall mode is: $fw_mode${NC}"
        return 0
    fi
}

# Configure IP forwarding
configure_forwarding() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Configuring IP forwarding...${NC}"

    # Check if already configured
    local ipv4_fwd=$($ssh_cmd "sysctl -n net.ipv4.ip_forward 2>/dev/null || echo '0'")
    local ipv6_fwd=$($ssh_cmd "sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo '0'")

    if [ "$ipv4_fwd" = "1" ] && [ "$ipv6_fwd" = "1" ]; then
        echo -e "  ${GREEN}[OK] IP forwarding already enabled${NC}"
        return 0
    fi

    # Add to sysctl.conf if not already present
    $ssh_cmd "grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
    $ssh_cmd "grep -q 'net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf 2>/dev/null || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf"

    # Apply immediately
    $ssh_cmd "sysctl -w net.ipv4.ip_forward=1" >/dev/null 2>&1
    $ssh_cmd "sysctl -w net.ipv6.conf.all.forwarding=1" >/dev/null 2>&1

    echo -e "  ${GREEN}[OK] IP forwarding enabled${NC}"
    return 0
}

# Configure firewall via UCI (idempotent)
configure_firewall() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Configuring firewall...${NC}"

    # Check if tailscale zone already exists
    local zone_exists=$($ssh_cmd "uci show firewall 2>/dev/null | grep -c \"name='tailscale'\" || true")

    if [ "$zone_exists" -gt 0 ]; then
        echo -e "  ${GREEN}[OK] Tailscale firewall zone already configured${NC}"
        return 0
    fi

    echo "  Creating Tailscale firewall zone..."

    # Create Tailscale zone with full access
    $ssh_cmd "uci add firewall zone" >/dev/null
    $ssh_cmd "uci set firewall.@zone[-1].name='tailscale'"
    $ssh_cmd "uci set firewall.@zone[-1].input='ACCEPT'"
    $ssh_cmd "uci set firewall.@zone[-1].output='ACCEPT'"
    $ssh_cmd "uci set firewall.@zone[-1].forward='REJECT'"
    $ssh_cmd "uci set firewall.@zone[-1].masq='1'"
    $ssh_cmd "uci add_list firewall.@zone[-1].device='tailscale0'"

    # Tailscale -> WAN forwarding (exit node)
    echo "  Adding Tailscale -> WAN forwarding (exit node)..."
    $ssh_cmd "uci add firewall forwarding" >/dev/null
    $ssh_cmd "uci set firewall.@forwarding[-1].src='tailscale'"
    $ssh_cmd "uci set firewall.@forwarding[-1].dest='wan'"

    # Tailscale -> LAN forwarding (subnet routing)
    echo "  Adding Tailscale -> LAN forwarding (subnet routing)..."
    $ssh_cmd "uci add firewall forwarding" >/dev/null
    $ssh_cmd "uci set firewall.@forwarding[-1].src='tailscale'"
    $ssh_cmd "uci set firewall.@forwarding[-1].dest='lan'"

    # LAN -> Tailscale forwarding (return traffic)
    echo "  Adding LAN -> Tailscale forwarding (return traffic)..."
    $ssh_cmd "uci add firewall forwarding" >/dev/null
    $ssh_cmd "uci set firewall.@forwarding[-1].src='lan'"
    $ssh_cmd "uci set firewall.@forwarding[-1].dest='tailscale'"

    # Commit and reload
    $ssh_cmd "uci commit firewall"
    $ssh_cmd "/etc/init.d/firewall reload" >/dev/null 2>&1

    echo -e "  ${GREEN}[OK] Firewall configured${NC}"
    return 0
}

# Configure sysupgrade persistence
configure_persistence() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Configuring sysupgrade persistence...${NC}"

    # Add paths to sysupgrade.conf if not present
    $ssh_cmd "grep -q '/etc/config/tailscale' /etc/sysupgrade.conf 2>/dev/null || echo '/etc/config/tailscale' >> /etc/sysupgrade.conf"
    $ssh_cmd "grep -q '/etc/tailscale/' /etc/sysupgrade.conf 2>/dev/null || echo '/etc/tailscale/' >> /etc/sysupgrade.conf"

    echo -e "  ${GREEN}[OK] Persistence configured${NC}"
    return 0
}

# Enable and start service
start_service() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Starting Tailscale service...${NC}"

    $ssh_cmd "/etc/init.d/tailscale enable" >/dev/null 2>&1
    $ssh_cmd "/etc/init.d/tailscale start" >/dev/null 2>&1

    # Wait for service to start
    sleep 2

    if $ssh_cmd "/etc/init.d/tailscale status" >/dev/null 2>&1; then
        echo -e "  ${GREEN}[OK] Tailscale service running${NC}"
        return 0
    else
        echo -e "  ${YELLOW}[WARN] Service may not be fully started yet${NC}"
        return 0
    fi
}

# Deploy Tailscale to a router
deploy_to_router() {
    local router=$1

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Deploying Tailscale to: $router${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    # Show router info
    show_ap_info "$router"
    echo

    # Test connectivity
    echo -e "${YELLOW}Testing connectivity...${NC}"
    if ! test_ap_connectivity "$router"; then
        echo -e "  ${RED}[FAIL] Router is not reachable${NC}"
        return 1
    fi
    echo -e "  ${GREEN}[OK] Router is reachable${NC}"
    echo

    local ssh_cmd=$(get_ap_ssh "$router")

    # Check if already installed
    if check_existing "$ssh_cmd"; then
        echo -e "${YELLOW}Tailscale is already installed on this router.${NC}"
        echo
        read -p "Reconfigure firewall and settings? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Skipping deployment."
            return 0
        fi
        echo
    else
        # Create backup before installation
        create_backup "$router"
        echo

        # Install Tailscale
        if ! install_tailscale "$ssh_cmd"; then
            return 1
        fi
        echo
    fi

    # Verify nftables mode
    verify_nftables "$ssh_cmd"
    echo

    # Configure IP forwarding
    configure_forwarding "$ssh_cmd"
    echo

    # Configure firewall
    configure_firewall "$ssh_cmd"
    echo

    # Configure persistence
    configure_persistence "$ssh_cmd"
    echo

    # Start service
    start_service "$ssh_cmd"
    echo

    return 0
}

# Get LAN subnet in CIDR notation from router
get_lan_subnet() {
    local ssh_cmd=$1

    # Try to get CIDR notation directly from ip command
    local network=$($ssh_cmd "ip -4 addr show br-lan 2>/dev/null | grep inet | awk '{print \$2}'" | head -1)

    if [ -n "$network" ]; then
        # Extract network address from CIDR (e.g., 10.19.19.1/24 -> 10.19.19.0/24)
        local ip_part=$(echo "$network" | cut -d/ -f1)
        local cidr=$(echo "$network" | cut -d/ -f2)
        # Zero out the host portion for common CIDR values
        local octets
        IFS='.' read -ra octets <<< "$ip_part"
        case "$cidr" in
            24) echo "${octets[0]}.${octets[1]}.${octets[2]}.0/24" ;;
            16) echo "${octets[0]}.${octets[1]}.0.0/16" ;;
            8)  echo "${octets[0]}.0.0.0/8" ;;
            *)  # For other CIDR values, use the IP with .0 suffix (approximation)
                echo "${octets[0]}.${octets[1]}.${octets[2]}.0/${cidr}" ;;
        esac
        return 0
    fi

    # Fallback: get from UCI
    local lan_ip=$($ssh_cmd "uci get network.lan.ipaddr 2>/dev/null")
    local netmask=$($ssh_cmd "uci get network.lan.netmask 2>/dev/null")

    if [ -n "$lan_ip" ]; then
        # Convert netmask to CIDR prefix
        local cidr
        case "$netmask" in
            255.255.255.0)   cidr=24 ;;
            255.255.0.0)     cidr=16 ;;
            255.0.0.0)       cidr=8 ;;
            255.255.255.128) cidr=25 ;;
            255.255.255.192) cidr=26 ;;
            255.255.255.224) cidr=27 ;;
            255.255.255.240) cidr=28 ;;
            255.255.255.248) cidr=29 ;;
            255.255.255.252) cidr=30 ;;
            255.255.254.0)   cidr=23 ;;
            255.255.252.0)   cidr=22 ;;
            255.255.248.0)   cidr=21 ;;
            255.255.240.0)   cidr=20 ;;
            *)               cidr=24 ;;  # fallback
        esac

        local octets
        IFS='.' read -ra octets <<< "$lan_ip"
        case "$cidr" in
            24) echo "${octets[0]}.${octets[1]}.${octets[2]}.0/24" ;;
            16) echo "${octets[0]}.${octets[1]}.0.0/16" ;;
            8)  echo "${octets[0]}.0.0.0/8" ;;
            *)  echo "${octets[0]}.${octets[1]}.${octets[2]}.0/${cidr}" ;;
        esac
        return 0
    fi

    # Ultimate fallback
    echo "192.168.1.0/24"
}

# Print next steps
print_next_steps() {
    local router=$1
    local ip=$(get_ap_ip "$router")
    local ssh_cmd=$(get_ap_ssh "$router")
    local lan_subnet=$(get_lan_subnet "$ssh_cmd")

    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                     NEXT STEPS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo "1. Authenticate Tailscale (generates auth URL):"
    echo -e "   ${YELLOW}ssh $router \"tailscale up --advertise-exit-node --advertise-routes=${lan_subnet}\"${NC}"
    echo
    echo "2. Visit the URL shown to authorize the device"
    echo
    echo "3. In Tailscale Admin Console (admin.tailscale.com):"
    echo "   - Enable 'Use as exit node' for this device"
    echo "   - Approve the advertised subnet route"
    echo
    echo "4. Verify deployment:"
    echo -e "   ${YELLOW}ssh $router \"tailscale status\"${NC}"
    echo -e "   ${YELLOW}ssh $router \"uci get tailscale.config.fw_mode\"${NC}"
    echo
    echo "5. Test from a remote Tailscale device:"
    echo "   - Exit node: curl -4 ifconfig.me (should show home IP)"
    echo "   - Subnet: ping $ip (should reach router)"
    echo
}

# Main execution
main() {
    print_header

    # Parse arguments
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi

    case "$1" in
        --list|-l)
            echo -e "${BLUE}Configured Access Points:${NC}"
            echo
            for ap in $(list_all_aps); do
                show_ap_info "$ap"
                echo
            done
            exit 0
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            ROUTER="$1"
            ;;
    esac

    # Validate router
    if ! ap_exists "$ROUTER"; then
        echo -e "${RED}Error: Router '$ROUTER' not found in configuration${NC}"
        echo
        echo "Available routers:"
        for ap in $(list_all_aps); do
            echo "  - $ap"
        done
        exit 1
    fi

    # Deploy
    if deploy_to_router "$ROUTER"; then
        print_next_steps "$ROUTER"
    else
        echo -e "${RED}Deployment failed!${NC}"
        exit 1
    fi
}

main "$@"
