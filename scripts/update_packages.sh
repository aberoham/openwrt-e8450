#!/bin/bash

# update_packages.sh - Apply package updates to E8450 routers
# Usage: ./update_packages.sh [router_name]
#        ./update_packages.sh           # Interactive mode - prompts for each router
#        ./update_packages.sh secondary-ap  # Update specific router
#        ./update_packages.sh all       # Update all routers (with confirmation)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Router configurations
ROUTERS=("secondary-ap" "primary-ap")

# Base directory (parent of scripts directory)
BASE_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"

# Log file
LOG_DIR="${BASE_DIR}/private/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/update_$(date +%Y%m%d_%H%M%S).log"

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     OpenWrt E8450 Package Updater - $(date +%Y-%m-%d)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to update packages on a single router
update_router() {
    local router=$1
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Updating: $router${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    log_message "Starting update for $router"
    
    # Check router connectivity
    if ! ping -c 1 -W 2 $(grep "Host $router" ~/.ssh/config -A 1 | grep HostName | awk '{print $2}') > /dev/null 2>&1; then
        echo -e "  ${RED}Router $router is not reachable${NC}"
        log_message "Router $router is not reachable"
        return 1
    fi
    
    # Update package lists
    echo "  Updating package lists..."
    if ! ssh $router "opkg update" > /dev/null 2>&1; then
        echo -e "  ${RED}Failed to update package lists${NC}"
        log_message "Failed to update package lists on $router"
        return 1
    fi
    
    # Check for available updates
    echo "  Checking for updates..."
    local updates=$(ssh $router "opkg list-upgradable" 2>/dev/null)
    local update_count=$(echo "$updates" | grep -c "^" || echo "0")
    
    if [ "$update_count" -eq 0 ]; then
        echo -e "  ${GREEN}No package updates available${NC}"
        log_message "No updates available for $router"
        return 0
    fi
    
    # Show available updates
    echo -e "  ${YELLOW}$update_count package(s) have updates:${NC}"
    echo "$updates" | head -20 | sed 's/^/    /'
    if [ "$update_count" -gt 20 ]; then
        echo "    ... and $((update_count - 20)) more"
    fi
    echo
    
    # Ask for confirmation
    echo -n "  Apply these updates to $router? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "  Skipping updates for $router"
        log_message "User skipped updates for $router"
        return 0
    fi
    
    # Create pre-update backup
    echo "  Creating pre-update backup..."
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${BASE_DIR}/private/device-data/${router}/backups"
    mkdir -p "$backup_dir"
    
    if ssh $router "sysupgrade -b /tmp/pre_update_backup.tar.gz" 2>/dev/null; then
        ssh $router "cat /tmp/pre_update_backup.tar.gz" > "${backup_dir}/pre_update_${timestamp}.tar.gz" 2>/dev/null
        ssh $router "rm -f /tmp/pre_update_backup.tar.gz" 2>/dev/null
        echo -e "  ${GREEN}✓ Backup created${NC}"
    else
        echo -e "  ${YELLOW}⚠ Backup failed, but continuing...${NC}"
        log_message "Warning: Pre-update backup failed for $router"
    fi
    
    # Apply updates
    echo "  Applying updates..."
    log_message "Applying updates to $router: $updates"
    
    # Get list of packages to upgrade
    local packages=$(echo "$updates" | awk '{print $1}')
    
    # Upgrade packages
    if ssh $router "opkg upgrade $packages" 2>&1 | tee -a "$LOG_FILE"; then
        echo -e "  ${GREEN}✓ Updates applied successfully${NC}"
        log_message "Updates completed successfully for $router"
    else
        echo -e "  ${RED}✗ Some updates may have failed${NC}"
        log_message "Some updates may have failed for $router"
    fi
    
    # Restart critical services if needed
    echo "  Restarting services..."
    
    # Check if uhttpd was updated
    if echo "$updates" | grep -q "uhttpd"; then
        ssh $router "/etc/init.d/uhttpd restart" 2>/dev/null
        echo "    ✓ Web server restarted"
    fi
    
    # Check if rpcd was updated
    if echo "$updates" | grep -q "rpcd"; then
        ssh $router "/etc/init.d/rpcd restart" 2>/dev/null
        echo "    ✓ RPC daemon restarted"
    fi
    
    # Check if dnsmasq was updated
    if echo "$updates" | grep -q "dnsmasq"; then
        ssh $router "/etc/init.d/dnsmasq restart" 2>/dev/null
        echo "    ✓ DNS/DHCP server restarted"
    fi
    
    # Check system status
    echo "  Verifying system status..."
    local uptime=$(ssh $router "uptime | awk -F'up' '{print \$2}' | awk -F',' '{print \$1}'" 2>/dev/null)
    local mem_free=$(ssh $router "free -m | grep Mem | awk '{print \$4}'" 2>/dev/null)
    
    echo "    Uptime: $uptime"
    echo "    Free memory: ${mem_free}MB"
    
    echo -e "  ${GREEN}✓ Update complete for $router${NC}"
    log_message "Update process completed for $router"
    
    return 0
}

# Main execution
TARGET="$1"

# Determine which routers to update
if [ -z "$TARGET" ]; then
    # Interactive mode - ask for each router
    for router in "${ROUTERS[@]}"; do
        echo -n "Update $router? (y/N): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            update_router "$router"
            echo
        else
            echo "Skipping $router"
            echo
        fi
    done
elif [ "$TARGET" = "all" ]; then
    # Update all routers
    echo -e "${YELLOW}Warning: This will update all routers.${NC}"
    echo -n "Continue? (y/N): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        # Always update secondary-ap first (test router)
        update_router "secondary-ap"
        echo
        echo -e "${YELLOW}Please test secondary-ap before continuing.${NC}"
        echo -n "Continue with primary-ap? (y/N): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            update_router "primary-ap"
        fi
    fi
elif [[ " ${ROUTERS[@]} " =~ " ${TARGET} " ]]; then
    # Update specific router
    update_router "$TARGET"
else
    echo -e "${RED}Invalid target: $TARGET${NC}"
    echo "Usage: $0 [router_name|all]"
    echo "Available routers: ${ROUTERS[*]}"
    exit 1
fi

# Summary
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                        SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo
echo "Update log saved to: $LOG_FILE"
echo
echo -e "${BLUE}Post-update checklist:${NC}"
echo "  □ Test internet connectivity"
echo "  □ Verify WiFi clients can connect"
echo "  □ Check WDS link status (if applicable)"
echo "  □ Access LuCI web interface"
echo "  □ Monitor logs for errors: ssh [router] 'logread -f'"
echo
echo -e "${BLUE}If issues occur:${NC}"
echo "  1. Check logs: ssh [router] 'logread | grep -i error'"
echo "  2. Restart services: ssh [router] '/etc/init.d/[service] restart'"
echo "  3. Restore backup if needed (see backup files in private/device-data/[router]/backups/)"
echo