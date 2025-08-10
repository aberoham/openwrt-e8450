#!/bin/bash

# check_updates.sh - Check for available updates on E8450 routers
# Usage: ./check_updates.sh [router_name|--all]
#        ./check_updates.sh              # Check all routers
#        ./check_updates.sh downstairs   # Check specific router

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"

# Load access point configuration
source "${BASE_DIR}/scripts/lib/ap_functions.sh"
check_ap_config

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     OpenWrt E8450 Update Check - $(date +%Y-%m-%d)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo

# Function to check updates for a single router
check_router_updates() {
    local router=$1
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Checking: $router${NC}"
    
    local role=$(get_ap_role "$router")
    local desc=$(get_ap_description "$router")
    if [ -n "$desc" ]; then
        echo -e "${GREEN}  $desc${NC}"
    fi
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Get current version
    echo -e "${YELLOW}Current Version:${NC}"
    $(get_ap_ssh "$router") "grep VERSION_ID /etc/os-release" 2>/dev/null || echo "  Unable to retrieve version"
    echo
    
    # Check for package updates
    echo -e "${YELLOW}Package Updates:${NC}"
    echo "  Updating package lists..."
    $(get_ap_ssh "$router") "opkg update > /dev/null 2>&1" 2>/dev/null || {
        echo -e "  ${RED}Failed to update package lists${NC}"
        return 1
    }
    
    # Count available updates
    update_count=$($(get_ap_ssh "$router") "opkg list-upgradable 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    
    if [ "$update_count" -gt 0 ]; then
        echo -e "  ${YELLOW}$update_count packages have updates available:${NC}"
        $(get_ap_ssh "$router") "opkg list-upgradable | head -10" 2>/dev/null
        if [ "$update_count" -gt 10 ]; then
            echo "  ... and $((update_count - 10)) more"
        fi
    else
        echo -e "  ${GREEN}All packages are up to date${NC}"
    fi
    echo
    
    # Check for firmware updates using owut
    echo -e "${YELLOW}Firmware Updates (via owut):${NC}"
    if $(get_ap_ssh "$router") "which owut > /dev/null 2>&1" 2>/dev/null; then
        # Try to check for firmware updates
        firmware_check=$($(get_ap_ssh "$router") "owut check 2>/dev/null" 2>/dev/null || echo "")
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

# Parse command line arguments
TARGET="$1"
ROUTERS_TO_CHECK=()

# Determine which routers to check
if [ -n "$TARGET" ] && [ "$TARGET" != "--all" ]; then
    # Specific router requested
    if ! ap_exists "$TARGET"; then
        echo -e "${RED}Router '$TARGET' not found in configuration${NC}"
        echo "Available routers: $(list_all_aps)"
        exit 1
    fi
    ROUTERS_TO_CHECK=("$TARGET")
else
    # Check all routers (default or --all)
    ROUTERS_TO_CHECK=($(list_all_aps))
fi

# Main execution
for router in "${ROUTERS_TO_CHECK[@]}"; do
    if test_ap_connectivity "$router"; then
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

for router in "${ROUTERS_TO_CHECK[@]}"; do
    if test_ap_connectivity "$router"; then
        update_count=$($(get_ap_ssh "$router") "opkg list-upgradable 2>/dev/null | wc -l" 2>/dev/null || echo "0")
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