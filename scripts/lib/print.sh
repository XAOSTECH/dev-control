#!/usr/bin/env bash
#
# Git-Control Shared Library: Print Helpers
# Common print functions for consistent terminal output
#
# Usage:
#   source "${SCRIPT_DIR}/lib/colors.sh"
#   source "${SCRIPT_DIR}/lib/print.sh"
#
# Note: colors.sh must be sourced first for colors to be available

# Print a styled header box with auto-padding
# Usage: print_header "Title Text" [width]
# The title will be centered automatically with proper padding
print_header() {
    local title="$1"
    local width=${2:-68}
    local title_len=${#title}
    local total_padding=$(( width - title_len))
    local left_padding=$(( total_padding / 2 ))
    local right_padding=$(( total_padding - left_padding ))
    
    echo -e "\n${BOLD}${BLUE}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    printf "${BOLD}${BLUE}║${NC}%*s${CYAN}%s${NC}%*s${BOLD}${BLUE}║${NC}\n" \
        "$left_padding" "" "$title" "$right_padding" ""
    echo -e "${BOLD}${BLUE}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}\n"
}

# Print info message
# Usage: print_info "message"
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Print success message
# Usage: print_success "message"
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Print warning message
# Usage: print_warning "message"
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Print error message
# Usage: print_error "message"
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Print debug message (only if DEBUG=true)
# Usage: print_debug "message"
print_debug() {
    if [[ "${DEBUG:-false}" == "true" || "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# Print step indicator
# Usage: print_step "Step description"
print_step() {
    echo -e "${CYAN}▶${NC} $1"
}

# Print a separator line
# Usage: print_separator [width]
print_separator() {
    local width=${1:-60}
    echo -e "${BLUE}$(printf '─%.0s' $(seq 1 $width))${NC}"
}

# Print a key-value pair
# Usage: print_kv "Key" "Value"
print_kv() {
    local key="$1"
    local value="$2"
    local width=${3:-20}
    printf "${CYAN}%-${width}s${NC} %s\n" "$key:" "$value"
}

# Confirm prompt (returns 0 for yes, 1 for no)
# Usage: if confirm "Proceed?"; then ...
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"
    local response
    
    if [[ "$default" =~ ^[Yy] ]]; then
        read -rp "${prompt} [Y/n]: " response
        [[ -z "$response" || "$response" =~ ^[Yy] ]]
    else
        read -rp "${prompt} [y/N]: " response
        [[ "$response" =~ ^[Yy] ]]
    fi
}
