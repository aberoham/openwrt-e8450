#!/bin/bash

# remove_tailscale.sh - Remove Tailscale from an OpenWrt router
# Usage: ./remove_tailscale.sh <router_name>
#        ./remove_tailscale.sh --list    # List configured routers
#
# Stops Tailscale, removes the package, and reverts firewall configuration.

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
    echo -e "${BLUE}      Tailscale Removal for OpenWrt - $(date +%Y-%m-%d)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
}

# Print usage
print_usage() {
    echo "Usage: $0 <router_name>"
    echo "       $0 --list     List configured routers"
    echo
    echo "This script removes Tailscale from an OpenWrt router:"
    echo "  - Stops and disables the Tailscale service"
    echo "  - Removes the Tailscale package"
    echo "  - Removes firewall rules (Tailscale zone and forwarding)"
    echo "  - Cleans up sysupgrade.conf entries"
}

# Check if Tailscale is installed
check_installed() {
    local ssh_cmd=$1

    if $ssh_cmd "opkg list-installed | grep -q tailscale" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Stop and disable service
stop_service() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Stopping Tailscale service...${NC}"

    # Disconnect from tailnet
    $ssh_cmd "tailscale down" >/dev/null 2>&1 || true

    # Stop service
    $ssh_cmd "/etc/init.d/tailscale stop" >/dev/null 2>&1 || true
    $ssh_cmd "/etc/init.d/tailscale disable" >/dev/null 2>&1 || true

    echo -e "  ${GREEN}[OK] Service stopped${NC}"
    return 0
}

# Remove Tailscale package
remove_package() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Removing Tailscale package...${NC}"

    if $ssh_cmd "opkg remove tailscale" 2>&1; then
        echo -e "  ${GREEN}[OK] Package removed${NC}"
        return 0
    else
        echo -e "  ${YELLOW}[WARN] Package removal had issues${NC}"
        return 0
    fi
}

# Find and remove tailscale firewall zone
remove_firewall_zone() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Removing firewall zone...${NC}"

    # Find the tailscale zone index
    local zone_count=$($ssh_cmd "uci show firewall 2>/dev/null | grep -c \"\.name='tailscale'\"" || echo "0")

    if [ "$zone_count" -eq 0 ]; then
        echo -e "  ${GREEN}[OK] No Tailscale zone found${NC}"
        return 0
    fi

    # Delete zones named 'tailscale' (iterate in reverse to avoid index shifting)
    # First, get list of all zone indices with name=tailscale
    local zones_to_delete=$($ssh_cmd "uci show firewall 2>/dev/null | grep \"\.name='tailscale'\" | sed \"s/firewall\\.@zone\\[\\([0-9]*\\)\\].*/\\1/\" | sort -rn" || echo "")

    for idx in $zones_to_delete; do
        echo "  Deleting zone at index $idx..."
        $ssh_cmd "uci delete firewall.@zone[$idx]" 2>/dev/null || true
    done

    echo -e "  ${GREEN}[OK] Zone(s) removed${NC}"
    return 0
}

# Remove tailscale forwarding rules
remove_firewall_forwarding() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Removing firewall forwarding rules...${NC}"

    # Remove forwarding rules that have tailscale as src or dest
    # Do this in a loop since indices shift after each deletion
    local removed=0
    local max_iterations=10

    for i in $(seq 1 $max_iterations); do
        # Find any forwarding with tailscale
        local fwd_idx=$($ssh_cmd "uci show firewall 2>/dev/null | grep '@forwarding.*tailscale' | head -1 | sed \"s/firewall\\.@forwarding\\[\\([0-9]*\\)\\].*/\\1/\"" || echo "")

        if [ -z "$fwd_idx" ]; then
            break
        fi

        $ssh_cmd "uci delete firewall.@forwarding[$fwd_idx]" 2>/dev/null || true
        ((removed++))
    done

    if [ "$removed" -gt 0 ]; then
        echo -e "  ${GREEN}[OK] Removed $removed forwarding rule(s)${NC}"
    else
        echo -e "  ${GREEN}[OK] No Tailscale forwarding rules found${NC}"
    fi

    return 0
}

# Commit and reload firewall
commit_firewall() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Applying firewall changes...${NC}"

    $ssh_cmd "uci commit firewall" 2>/dev/null || true
    $ssh_cmd "/etc/init.d/firewall reload" >/dev/null 2>&1 || true

    echo -e "  ${GREEN}[OK] Firewall reloaded${NC}"
    return 0
}

# Clean up sysupgrade.conf
cleanup_sysupgrade() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Cleaning up sysupgrade.conf...${NC}"

    # Remove tailscale-related lines from sysupgrade.conf
    $ssh_cmd "sed -i '/tailscale/d' /etc/sysupgrade.conf" 2>/dev/null || true

    echo -e "  ${GREEN}[OK] Cleanup complete${NC}"
    return 0
}

# Clean up Tailscale state directory
cleanup_state() {
    local ssh_cmd=$1

    echo -e "${YELLOW}Cleaning up Tailscale state...${NC}"

    $ssh_cmd "rm -rf /etc/tailscale" 2>/dev/null || true
    $ssh_cmd "rm -rf /etc/config/tailscale" 2>/dev/null || true

    echo -e "  ${GREEN}[OK] State cleaned up${NC}"
    return 0
}

# Remove Tailscale from a router
remove_from_router() {
    local router=$1

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Removing Tailscale from: $router${NC}"
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

    # Check if installed
    if ! check_installed "$ssh_cmd"; then
        echo -e "${YELLOW}Tailscale is not installed on this router.${NC}"
        echo
        read -p "Remove firewall rules anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Nothing to do."
            return 0
        fi
    else
        # Confirm removal
        echo -e "${RED}WARNING: This will remove Tailscale and disconnect from the tailnet.${NC}"
        echo
        read -p "Are you sure you want to continue? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
        echo

        # Stop service
        stop_service "$ssh_cmd"
        echo

        # Remove package
        remove_package "$ssh_cmd"
        echo
    fi

    # Remove firewall configuration
    remove_firewall_zone "$ssh_cmd"
    remove_firewall_forwarding "$ssh_cmd"
    commit_firewall "$ssh_cmd"
    echo

    # Clean up
    cleanup_sysupgrade "$ssh_cmd"
    cleanup_state "$ssh_cmd"
    echo

    return 0
}

# Print summary
print_summary() {
    local router=$1

    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    REMOVAL COMPLETE${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo "Tailscale has been removed from $router."
    echo
    echo "What was removed:"
    echo "  - Tailscale package"
    echo "  - Tailscale firewall zone"
    echo "  - Forwarding rules (tailscale -> wan, tailscale -> lan, lan -> tailscale)"
    echo "  - Tailscale state directory (/etc/tailscale)"
    echo "  - Sysupgrade persistence entries"
    echo
    echo "Note: The device will remain in your Tailscale admin console."
    echo "To fully remove it, go to admin.tailscale.com and delete the machine."
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

    # Remove
    if remove_from_router "$ROUTER"; then
        print_summary "$ROUTER"
    else
        echo -e "${RED}Removal failed!${NC}"
        exit 1
    fi
}

main "$@"
