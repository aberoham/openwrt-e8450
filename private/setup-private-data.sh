#!/bin/bash

# setup-private-data.sh - Set up private data repository and symlinks
# This script creates symlinks from the main repository to a private data repository

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
PRIVATE_REPO_PATH="${HOME}/openwrt-e8450-private"
PRIVATE_REPO_URL="https://github.com/YOUR_USERNAME/openwrt-e8450-private.git"

echo -e "${BLUE}OpenWrt E8450 Private Data Setup${NC}"
echo -e "${BLUE}=================================${NC}"
echo

# Check if private repo exists
if [ ! -d "$PRIVATE_REPO_PATH" ]; then
    echo -e "${YELLOW}Private repository not found at: $PRIVATE_REPO_PATH${NC}"
    echo
    echo "Would you like to:"
    echo "1) Clone the private repository (requires access)"
    echo "2) Create a new private data structure"
    echo "3) Exit"
    echo
    read -p "Choose option [1-3]: " choice
    
    case $choice in
        1)
            echo -e "${BLUE}Cloning private repository...${NC}"
            if git clone "$PRIVATE_REPO_URL" "$PRIVATE_REPO_PATH"; then
                echo -e "${GREEN}✓ Private repository cloned successfully${NC}"
            else
                echo -e "${RED}✗ Failed to clone repository. Check your access permissions.${NC}"
                exit 1
            fi
            ;;
        2)
            echo -e "${BLUE}Creating new private data structure...${NC}"
            mkdir -p "$PRIVATE_REPO_PATH"/{device-data/{primary-ap,secondary-ap}/{backups,config},firmware/{boot-backup,releases,installers},historical-backups,logs}
            echo "# OpenWrt E8450 Private Data" > "$PRIVATE_REPO_PATH/README.md"
            echo -e "${GREEN}✓ Private data structure created${NC}"
            echo
            echo "You can now place your configuration files in:"
            echo "  $PRIVATE_REPO_PATH"
            ;;
        3)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            exit 1
            ;;
    esac
else
    echo -e "${GREEN}✓ Private repository found at: $PRIVATE_REPO_PATH${NC}"
fi

echo
echo -e "${BLUE}Creating symlinks...${NC}"

# Function to create symlink
create_symlink() {
    local source=$1
    local target=$2
    local name=$3
    
    # Remove existing symlink or directory
    if [ -L "$target" ] || [ -e "$target" ]; then
        rm -rf "$target"
    fi
    
    # Create symlink
    if ln -s "$source" "$target"; then
        echo -e "  ${GREEN}✓${NC} $name"
    else
        echo -e "  ${RED}✗${NC} $name (failed)"
        return 1
    fi
}

# Ensure we're in the main repo directory (parent of private/)
if [ "$(basename "$(pwd)")" = "private" ]; then
    cd ..
fi

# Create private directory if it doesn't exist
mkdir -p private

# Create symlinks in private subdirectory
create_symlink "$PRIVATE_REPO_PATH/device-data" "private/device-data" "device-data"
create_symlink "$PRIVATE_REPO_PATH/firmware" "private/binaries" "binaries → firmware"
create_symlink "$PRIVATE_REPO_PATH/historical-backups" "private/old-backups" "old-backups → historical-backups"
create_symlink "$PRIVATE_REPO_PATH/logs" "private/logs" "logs"

echo
echo -e "${BLUE}Verifying symlinks...${NC}"

# Verify symlinks
for link in device-data binaries old-backups logs; do
    if [ -L "private/$link" ]; then
        target=$(readlink "private/$link")
        echo -e "  ${GREEN}✓${NC} private/$link → $target"
    else
        echo -e "  ${RED}✗${NC} private/$link is not a symlink"
    fi
done

echo
echo -e "${BLUE}Checking access points configuration...${NC}"

# Check and create accesspoints.conf if it doesn't exist
AP_CONFIG="$PRIVATE_REPO_PATH/device-data/accesspoints.conf"
if [ ! -f "$AP_CONFIG" ]; then
    echo -e "${YELLOW}Creating access points configuration template...${NC}"
    cat > "$AP_CONFIG" << 'EOF'
#!/bin/bash
# Access Points Configuration File
# 
# IMPORTANT: Replace these example entries with your actual access points!
# 
# Format: "name:role:ip:user:port:description"
#   name        - Friendly name for the access point (no spaces)
#   role        - Either "primary" (main gateway) or "secondary" (mesh/WDS nodes)
#   ip          - IP address of the access point
#   user        - SSH username (usually "root" for OpenWrt)
#   port        - SSH port (usually 22)
#   description - Optional description of the access point
#
# Example network with 3 access points:
#   - Main router downstairs (primary gateway)
#   - Upstairs extension (secondary via WDS)
#   - Garage access point (secondary via WDS)

# Define your access points here
ACCESS_POINTS=(
  # REPLACE THESE WITH YOUR ACTUAL ACCESS POINTS:
  "primary-ap:primary:192.168.1.1:root:22:Main gateway router"
  "secondary-ap:secondary:192.168.1.2:root:22:Secondary access point"
  # Add more access points as needed:
  # "garage-ap:secondary:192.168.1.3:root:22:Garage access point"
  # "guest-house:secondary:192.168.1.4:root:22:Guest house AP"
)

# Update order - which routers to update first
# Best practice: Update secondary/test routers first, primary last
UPDATE_ORDER=("secondary-ap" "primary-ap")
# If you have multiple secondaries, list them before the primary:
# UPDATE_ORDER=("upstairs" "garage" "guest-house" "downstairs")

# Configuration settings
BACKUP_RETENTION=10        # Number of backups to keep per router
SSH_TIMEOUT=5             # SSH connection timeout in seconds
DEFAULT_USER="root"       # Default SSH user if not specified in ACCESS_POINTS
DEFAULT_PORT="22"         # Default SSH port if not specified in ACCESS_POINTS

# SSH Options (used by all scripts)
SSH_OPTIONS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=${SSH_TIMEOUT}"
EOF
    echo -e "  ${GREEN}✓${NC} Created template: device-data/accesspoints.conf"
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  IMPORTANT: Configure your access points!${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Edit the configuration file:"
    echo -e "    ${BLUE}private/device-data/accesspoints.conf${NC}"
    echo
    echo "  Replace the example entries with your actual routers."
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
else
    echo -e "  ${GREEN}✓${NC} Access points configuration already exists"
fi

echo
echo -e "${GREEN}Private data setup complete!${NC}"
echo
echo "Your repository structure:"
echo "  Main repo: $(pwd)"
echo "  Private data: $PRIVATE_REPO_PATH"
echo
echo "The following symlinks have been created:"
echo "  private/device-data → $PRIVATE_REPO_PATH/device-data"
echo "  private/binaries → $PRIVATE_REPO_PATH/firmware"
echo "  private/old-backups → $PRIVATE_REPO_PATH/historical-backups"
echo "  private/logs → $PRIVATE_REPO_PATH/logs"
echo
if [ ! -f "$AP_CONFIG" ] || grep -q "192.168.1.1" "$AP_CONFIG" 2>/dev/null; then
    echo -e "${YELLOW}Next step: Configure your access points in:${NC}"
    echo -e "  ${BLUE}private/device-data/accesspoints.conf${NC}"
    echo
fi
echo -e "${YELLOW}Note: The private directory is in .gitignore and won't be committed.${NC}"
