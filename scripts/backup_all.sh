#!/bin/bash

# backup_all.sh - Create configuration backups for both E8450 routers
# Usage: ./backup_all.sh

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
    
    # Check router connectivity
    if ! ping -c 1 -W 2 $(grep "Host $router" ~/.ssh/config -A 1 | grep HostName | awk '{print $2}') > /dev/null 2>&1; then
        echo -e "  ${RED}Router $router is not reachable${NC}"
        return 1
    fi
    
    # Create backup
    echo "  Creating configuration backup..."
    if ssh $router "sysupgrade -b /tmp/backup_temp.tar.gz" 2>/dev/null; then
        # Transfer backup file
        echo "  Transferring backup file..."
        if ssh $router "cat /tmp/backup_temp.tar.gz" > "$backup_file" 2>/dev/null; then
            # Clean up temp file on router
            ssh $router "rm -f /tmp/backup_temp.tar.gz" 2>/dev/null
            
            # Verify backup file
            if [ -f "$backup_file" ]; then
                local size=$(ls -lh "$backup_file" | awk '{print $5}')
                echo -e "  ${GREEN}✓ Backup created successfully${NC}"
                echo "    File: $backup_file"
                echo "    Size: $size"
                
                # Also backup individual config files for easy access
                local config_dir="${BASE_DIR}/private/device-data/${router}/config"
                mkdir -p "$config_dir"
                
                echo "  Backing up individual config files..."
                for config in network wireless firewall dhcp system; do
                    if ssh $router "uci export $config" > "${config_dir}/${config}" 2>/dev/null; then
                        echo "    ✓ $config"
                    else
                        echo "    ✗ $config (failed)"
                    fi
                done
                
                return 0
            else
                echo -e "  ${RED}Failed to create backup file${NC}"
                return 1
            fi
        else
            echo -e "  ${RED}Failed to transfer backup${NC}"
            ssh $router "rm -f /tmp/backup_temp.tar.gz" 2>/dev/null
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

# Main execution
SUCCESS_COUNT=0
FAIL_COUNT=0

for router in "${ROUTERS[@]}"; do
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

if [ "$SUCCESS_COUNT" -eq "${#ROUTERS[@]}" ]; then
    echo -e "  ${GREEN}All routers backed up successfully!${NC}"
else
    echo -e "  ${GREEN}Successful: $SUCCESS_COUNT${NC}"
    echo -e "  ${RED}Failed: $FAIL_COUNT${NC}"
fi

echo
echo -e "${BLUE}Backup locations:${NC}"
for router in "${ROUTERS[@]}"; do
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