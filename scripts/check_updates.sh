#!/bin/bash

# check_updates.sh - Check for available updates on both E8450 routers
# Usage: ./check_updates.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Router configurations
ROUTERS=("secondary-ap" "primary-ap")

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     OpenWrt E8450 Update Check - $(date +%Y-%m-%d)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo

# Function to check updates for a single router
check_router_updates() {
    local router=$1
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Checking: $router${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Get current version
    echo -e "${YELLOW}Current Version:${NC}"
    ssh $router "grep VERSION_ID /etc/os-release" 2>/dev/null || echo "  Unable to retrieve version"
    echo
    
    # Check for package updates
    echo -e "${YELLOW}Package Updates:${NC}"
    echo "  Updating package lists..."
    ssh $router "opkg update > /dev/null 2>&1" 2>/dev/null || {
        echo -e "  ${RED}Failed to update package lists${NC}"
        return 1
    }
    
    # Count available updates
    update_count=$(ssh $router "opkg list-upgradable 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    
    if [ "$update_count" -gt 0 ]; then
        echo -e "  ${YELLOW}$update_count packages have updates available:${NC}"
        ssh $router "opkg list-upgradable | head -10" 2>/dev/null
        if [ "$update_count" -gt 10 ]; then
            echo "  ... and $((update_count - 10)) more"
        fi
    else
        echo -e "  ${GREEN}All packages are up to date${NC}"
    fi
    echo
    
    # Check for firmware updates using owut
    echo -e "${YELLOW}Firmware Updates (via owut):${NC}"
    if ssh $router "which owut > /dev/null 2>&1" 2>/dev/null; then
        # Try to check for firmware updates
        firmware_check=$(ssh $router "owut check 2>/dev/null" 2>/dev/null || echo "")
        if [ -n "$firmware_check" ]; then
            echo "$firmware_check" | grep -E "(Current|Available|Latest)" | sed 's/^/  /'
        else
            echo "  Unable to check firmware updates (owut not configured or server unavailable)"
        fi
    else
        echo -e "  ${RED}owut not installed - cannot check for firmware updates${NC}"
        echo "  Install with: opkg install owut"
    fi
    echo
}

# Main execution
for router in "${ROUTERS[@]}"; do
    if ping -c 1 -W 2 $(ssh $router "echo \$SSH_CONNECTION" 2>/dev/null | awk '{print $3}') > /dev/null 2>&1; then
        check_router_updates "$router"
    else
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  $router: UNREACHABLE${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
    fi
done

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                        SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

for router in "${ROUTERS[@]}"; do
    if ping -c 1 -W 2 $(ssh $router "echo \$SSH_CONNECTION" 2>/dev/null | awk '{print $3}') > /dev/null 2>&1; then
        update_count=$(ssh $router "opkg list-upgradable 2>/dev/null | wc -l" 2>/dev/null || echo "0")
        if [ "$update_count" -gt 0 ]; then
            echo -e "  $router: ${YELLOW}$update_count package updates available${NC}"
        else
            echo -e "  $router: ${GREEN}Up to date${NC}"
        fi
    else
        echo -e "  $router: ${RED}Unreachable${NC}"
    fi
done

echo
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Review the updates above"
echo "  2. Run ./backup_all.sh to create backups"
echo "  3. Run ./update_packages.sh to apply package updates"
echo "  4. For firmware updates, use: ssh [router] 'owut upgrade'"
echo