#!/bin/bash

# backup_all.sh - Create configuration backups for E8450 routers
# Usage: ./backup_all.sh [router_name|--role role|--all]
#        ./backup_all.sh                  # Backup all routers
#        ./backup_all.sh downstairs       # Backup specific router
#        ./backup_all.sh --role secondary # Backup all secondary APs
#        ./backup_all.sh --list           # List configured routers

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

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     OpenWrt E8450 Backup Tool - $(date +%Y-%m-%d)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo

# Function to backup a single router
backup_router() {
    local router=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${BASE_DIR}/private/device-data/${router}/backups"
    local backup_file="${backup_dir}/backup_${timestamp}.tar.gz"
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Backing up: $router${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"
    
    # Get router details
    local role=$(get_ap_role "$router")
    local desc=$(get_ap_description "$router")
    if [ -n "$desc" ]; then
        echo "  Description: $desc"
    fi
    echo "  Role: $role"
    
    # Check router connectivity
    if ! test_ap_connectivity "$router"; then
        echo -e "  ${RED}Router $router is not reachable${NC}"
        return 1
    fi
    
    # Create backup
    echo "  Creating configuration backup..."
    local ssh_cmd=$(get_ap_ssh "$router")
    if $ssh_cmd "sysupgrade -b /tmp/backup_temp.tar.gz" 2>/dev/null; then
        # Transfer backup file
        echo "  Transferring backup file..."
        if $ssh_cmd "cat /tmp/backup_temp.tar.gz" > "$backup_file" 2>/dev/null; then
            # Clean up temp file on router
            $ssh_cmd "rm -f /tmp/backup_temp.tar.gz" 2>/dev/null
            
            # Verify backup file
            if [ -f "$backup_file" ]; then
                local size=$(ls -lh "$backup_file" | awk '{print $5}')
                echo -e "  ${GREEN}[OK] Backup created successfully${NC}"
                echo "    File: $backup_file"
                echo "    Size: $size"
                
                # Also backup individual config files for easy access
                local config_dir="${BASE_DIR}/private/device-data/${router}/config"
                mkdir -p "$config_dir"
                
                echo "  Backing up individual config files..."
                for config in network wireless firewall dhcp system; do
                    if $ssh_cmd "uci export $config" > "${config_dir}/${config}" 2>/dev/null; then
                        echo "    [OK] $config"
                    else
                        echo "    [FAIL] $config"
                    fi
                done
                
                return 0
            else
                echo -e "  ${RED}Failed to create backup file${NC}"
                return 1
            fi
        else
            echo -e "  ${RED}Failed to transfer backup${NC}"
            $ssh_cmd "rm -f /tmp/backup_temp.tar.gz" 2>/dev/null
            return 1
        fi
    else
        echo -e "  ${RED}Failed to create backup on router${NC}"
        return 1
    fi
}

# Function to clean old backups (keep last N backups)
clean_old_backups() {
    local router=$1
    local keep_count=10  # Keep last 10 backups
    local backup_dir="${BASE_DIR}/private/device-data/${router}/backups"
    
    if [ -d "$backup_dir" ]; then
        local backup_count=$(ls -1 "$backup_dir"/backup_*.tar.gz 2>/dev/null | wc -l)
        if [ "$backup_count" -gt "$keep_count" ]; then
            local remove_count=$((backup_count - keep_count))
            echo "  Removing $remove_count old backup(s)..."
            ls -1t "$backup_dir"/backup_*.tar.gz | tail -n "$remove_count" | xargs rm -f
        fi
    fi
}

# Parse command line arguments
TARGET="$1"
ROUTERS_TO_BACKUP=()

# Determine which routers to backup
if [ "$TARGET" = "--list" ]; then
    echo -e "${BLUE}Configured Access Points:${NC}"
    for ap in $(list_all_aps); do
        show_ap_info "$ap"
        echo
    done
    exit 0
elif [ "$TARGET" = "--role" ]; then
    ROLE="$2"
    if [ -z "$ROLE" ]; then
        echo -e "${RED}Error: --role requires a role name (primary/secondary)${NC}"
        exit 1
    fi
    ROUTERS_TO_BACKUP=($(list_by_role "$ROLE"))
    if [ ${#ROUTERS_TO_BACKUP[@]} -eq 0 ]; then
        echo -e "${RED}No routers found with role: $ROLE${NC}"
        exit 1
    fi
    echo -e "${BLUE}Backing up all $ROLE routers: ${ROUTERS_TO_BACKUP[*]}${NC}"
elif [ -n "$TARGET" ] && [ "$TARGET" != "--all" ]; then
    # Specific router requested
    if ! ap_exists "$TARGET"; then
        echo -e "${RED}Router '$TARGET' not found in configuration${NC}"
        echo "Available routers: $(list_all_aps)"
        exit 1
    fi
    ROUTERS_TO_BACKUP=("$TARGET")
else
    # Backup all routers (default or --all)
    ROUTERS_TO_BACKUP=($(list_all_aps))
fi

# Main execution
SUCCESS_COUNT=0
FAIL_COUNT=0

for router in "${ROUTERS_TO_BACKUP[@]}"; do
    if backup_router "$router"; then
        clean_old_backups "$router"
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
    echo
done

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                        SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

if [ "$SUCCESS_COUNT" -eq "${#ROUTERS_TO_BACKUP[@]}" ]; then
    echo -e "  ${GREEN}All routers backed up successfully!${NC}"
else
    echo -e "  ${GREEN}Successful: $SUCCESS_COUNT${NC}"
    echo -e "  ${RED}Failed: $FAIL_COUNT${NC}"
fi

echo
echo -e "${BLUE}Backup locations:${NC}"
for router in "${ROUTERS_TO_BACKUP[@]}"; do
    backup_dir="${BASE_DIR}/private/device-data/${router}/backups"
    if [ -d "$backup_dir" ]; then
        latest=$(ls -1t "$backup_dir"/backup_*.tar.gz 2>/dev/null | head -1)
        if [ -n "$latest" ]; then
            echo "  $router: $(basename "$latest")"
        fi
    fi
done

echo
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Backups are complete and stored locally"
echo "  2. You can now safely run update scripts"
echo "  3. To restore a backup: scp [backup] router:/tmp/ && ssh router 'sysupgrade -r /tmp/[backup]'"
echo