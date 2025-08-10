#!/bin/bash

# ap_functions.sh - Shared functions for access point management
# This library provides common functions for working with the access points configuration

# Colors for output (if not already defined)
if [ -z "$RED" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# Determine base paths
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="${BASE_DIR}/private/device-data/accesspoints.conf"

# Check and load access points configuration
check_ap_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}              ACCESS POINTS NOT CONFIGURED${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        echo
        echo "The access points configuration file was not found."
        echo
        echo "Please run the setup script first:"
        echo -e "  ${YELLOW}./private/setup-private-data.sh${NC}"
        echo
        echo "Then edit the configuration file with your router details:"
        echo -e "  ${YELLOW}private/device-data/accesspoints.conf${NC}"
        echo
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        exit 1
    fi
    
    # Source the configuration
    source "$CONFIG_FILE"
    
    # Check if configuration exists but is empty
    if [ ${#ACCESS_POINTS[@]} -eq 0 ]; then
        echo -e "${RED}ERROR: No access points defined in configuration!${NC}"
        echo "Please edit: private/device-data/accesspoints.conf"
        exit 1
    fi
    
    # Check if still using default/example values
    local using_defaults=false
    for ap in "${ACCESS_POINTS[@]}"; do
        if [[ "$ap" == *"192.168.1.1"* ]] || [[ "$ap" == *"192.168.1.2"* ]]; then
            using_defaults=true
            break
        fi
    done
    
    if [ "$using_defaults" = true ]; then
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}        WARNING: Using Example Configuration${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
        echo
        echo "The configuration file contains example IP addresses."
        echo "Please edit: private/device-data/accesspoints.conf"
        echo "Update it with your actual access point details."
        echo
        read -p "Continue anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
        echo
    fi
}

# Get a specific field from an access point entry
# Usage: get_ap_field "ap_name" field_number
# Fields: 1=name, 2=role, 3=ip, 4=user, 5=port, 6=description
get_ap_field() {
    local ap_name=$1
    local field_num=$2
    
    for ap in "${ACCESS_POINTS[@]}"; do
        local name=$(echo "$ap" | cut -d: -f1)
        if [ "$name" = "$ap_name" ]; then
            echo "$ap" | cut -d: -f$field_num
            return 0
        fi
    done
    return 1
}

# Get the full access point entry by name
get_ap_entry() {
    local ap_name=$1
    
    for ap in "${ACCESS_POINTS[@]}"; do
        local name=$(echo "$ap" | cut -d: -f1)
        if [ "$name" = "$ap_name" ]; then
            echo "$ap"
            return 0
        fi
    done
    return 1
}

# Build SSH command for an access point
# Usage: $(get_ap_ssh "ap_name") "command"
get_ap_ssh() {
    local ap_name=$1
    local ip=$(get_ap_field "$ap_name" 3)
    local user=$(get_ap_field "$ap_name" 4)
    local port=$(get_ap_field "$ap_name" 5)
    
    if [ -z "$ip" ]; then
        echo "ssh $ap_name"  # Fallback to hostname if not found
        return 1
    fi
    
    # Use defaults if not specified
    user=${user:-${DEFAULT_USER:-root}}
    port=${port:-${DEFAULT_PORT:-22}}
    
    echo "ssh ${SSH_OPTIONS:-} -p $port ${user}@${ip}"
}

# Get IP address for an access point
get_ap_ip() {
    local ap_name=$1
    get_ap_field "$ap_name" 3
}

# Get role for an access point (primary/secondary)
get_ap_role() {
    local ap_name=$1
    get_ap_field "$ap_name" 2
}

# Get description for an access point
get_ap_description() {
    local ap_name=$1
    get_ap_field "$ap_name" 6
}

# List all access point names
list_all_aps() {
    for ap in "${ACCESS_POINTS[@]}"; do
        echo "$ap" | cut -d: -f1
    done
}

# List access points by role
# Usage: list_by_role "primary" or list_by_role "secondary"
list_by_role() {
    local role=$1
    
    for ap in "${ACCESS_POINTS[@]}"; do
        local ap_role=$(echo "$ap" | cut -d: -f2)
        if [ "$ap_role" = "$role" ]; then
            echo "$ap" | cut -d: -f1
        fi
    done
}

# Check if an access point exists in configuration
ap_exists() {
    local ap_name=$1
    
    for ap in "${ACCESS_POINTS[@]}"; do
        local name=$(echo "$ap" | cut -d: -f1)
        if [ "$name" = "$ap_name" ]; then
            return 0
        fi
    done
    return 1
}

# Test connectivity to an access point
test_ap_connectivity() {
    local ap_name=$1
    local ip=$(get_ap_ip "$ap_name")
    
    if [ -z "$ip" ]; then
        return 1
    fi
    
    ping -c 1 -W 2 "$ip" > /dev/null 2>&1
}

# Display access point information
show_ap_info() {
    local ap_name=$1
    
    if ! ap_exists "$ap_name"; then
        echo -e "${RED}Access point '$ap_name' not found in configuration${NC}"
        return 1
    fi
    
    local role=$(get_ap_role "$ap_name")
    local ip=$(get_ap_ip "$ap_name")
    local desc=$(get_ap_description "$ap_name")
    
    echo "  Name: $ap_name"
    echo "  Role: $role"
    echo "  IP:   $ip"
    [ -n "$desc" ] && echo "  Desc: $desc"
}

# Get the update order array (if defined)
get_update_order() {
    if [ ${#UPDATE_ORDER[@]} -gt 0 ]; then
        echo "${UPDATE_ORDER[@]}"
    else
        # If no update order defined, use secondaries first, then primary
        list_by_role "secondary"
        list_by_role "primary"
    fi
}