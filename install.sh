#!/bin/bash

# VAULT_OPUS - STANDALONE LINUX INSTALLER
# A robust script to bootstrap Python, Node.js, and project requirements.

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Banner ---
clear
echo -e "${CYAN}${BOLD}"
echo " __      __    _    _   _ _   _______    ____   _____  _    _  _____ "
echo " \ \    / /   / \  | | | | | |__   __|  / __ \ |  __ \| |  | |/ ____|"
echo "  \ \  / /   / _ \ | | | | |    | |    | |  | || |__) | |  | | (___  "
echo "   \ \/ /   / ___ \| | | | |    | |    | |  | ||  ___/| |  | |\___ \ "
echo "    \  /   / /   \ \ |_| | |____| |    | |__| || |    | |__| |____) |"
echo "     \/   /_/     \_\____|______|_|     \____/ |_|     \____/|_____/ "
echo -e "${NC}"
echo -e "${BLUE}${BOLD}>>> THE INFINITY CLOUD STORAGE PROJECT <<< ${NC}\n"

# --- Helper Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. Bootstrap Python ---
log_info "Checking for Python 3..."
if ! command -v python3 &> /dev/null; then
    log_warning "Python 3 not found. Attempting to install..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv
    else
        log_error "Could not find apt-get. Please install Python 3 manually."
        exit 1
    fi
fi
log_success "Python $(python3 --version) detected."

# --- 2. Bootstrap Node.js ---
log_info "Checking for Node.js & NPM..."
INSTALL_FRONTEND=true
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    log_warning "Node.js/NPM not found."
    read -p "Would you like to attempt to install Node.js? (y/n): " install_node
    if [[ $install_node == "y" ]]; then
        if command -v apt-get &> /dev/null; then
            log_info "Installing Node.js via Nodesource..."
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
        else
            log_error "Automatic Node.js install only supported on Debian/Ubuntu. Please install manually."
            INSTALL_FRONTEND=false
        fi
    else
        INSTALL_FRONTEND=false
    fi
fi

if [[ $INSTALL_FRONTEND == "true" ]]; then
    log_success "Node.js $(node -v) and NPM $(npm -v) detected."
fi

# --- 3. Virtual Environment & Dependencies ---
if [ ! -d "venv" ]; then
    log_info "Creating Virtual Environment (venv)..."
    python3 -m venv venv || { log_error "Failed to create venv. Please install python3-venv."; exit 1; }
fi

log_info "Activating Virtual Environment..."
source venv/bin/activate

log_info "Installing Python dependencies from requirements.txt..."
if pip install -r requirements.txt; then
    log_success "All Python dependencies installed."
else
    log_error "Failed to install Python dependencies."
    exit 1
fi

# --- 4. Interactive Configuration ---
log_info "Setting up config.json..."
CONFIG_FILE="src/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    # Create minimal default if missing
    mkdir -p src
    echo '{"discord": {"token": "", "channel_id": "", "command_prefix": "/"}}' > "$CONFIG_FILE"
fi

echo -e "\n${BOLD}--- Discord Bot Configuration ---${NC}"
read -p "Enter your Discord Bot Token (leave empty to keep current): " TOKEN
read -p "Enter your Discord Channel ID (leave empty to keep current): " CHANNEL_ID

# Clean up input (strip quotes and trailing commas)
TOKEN=$(echo "$TOKEN" | sed 's/[",]//g')
CHANNEL_ID=$(echo "$CHANNEL_ID" | sed 's/[",]//g')

if command -v jq &> /dev/null; then
    if [ ! -z "$TOKEN" ]; then
        jq ".discord.token = \"$TOKEN\"" "$CONFIG_FILE" > config.tmp && mv config.tmp "$CONFIG_FILE"
    fi
    if [ ! -z "$CHANNEL_ID" ]; then
        jq ".discord.channel_id = \"$CHANNEL_ID\"" "$CONFIG_FILE" > config.tmp && mv config.tmp "$CONFIG_FILE"
    fi
else
    # Fallback to python if jq is missing
    python3 -c "import json, sys; d=json.load(open('$CONFIG_FILE')); 
if '$TOKEN': d['discord']['token']='$TOKEN'
if '$CHANNEL_ID': d['discord']['channel_id']='$CHANNEL_ID'
json.dump(d, open('$CONFIG_FILE', 'w'), indent=2)" 2>/dev/null
fi
log_success "Configuration updated."

# --- 5. Frontend Setup ---
if [[ $INSTALL_FRONTEND == "true" ]]; then
    echo -e "\n${BOLD}--- Frontend Setup ---${NC}"
    read -p "Install npm packages for Web & Mobile? (y/n): " do_npm
    if [[ $do_npm == "y" ]]; then
        for dir in "src/WI/client" "src/WI/mobile"; do
            if [ -d "$dir" ]; then
                log_info "Running npm install in $dir..."
                (cd "$dir" && npm install)
            fi
        done
        log_success "Frontend dependencies installed."
    fi
fi

echo -e "\n${GREEN}${BOLD}VAULT_OPUS Installation Complete!${NC}"
echo "Run the app with:"
echo "  - Backend: ./venv/bin/python3 src/VAULT_OPUS.py"
echo "  - Web GUI: ./venv/bin/python3 src/WI/server.py"
echo -e "\n${CYAN}Enjoy!${NC}\n"
