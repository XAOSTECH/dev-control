#!/usr/bin/env bash
#
# Dev-Control Shared Library: Print Helpers
# Common print functions for consistent terminal output
#
# Usage:
#   source "${SCRIPT_DIR}/lib/colours.sh"
#   source "${SCRIPT_DIR}/lib/print.sh"
#
# Note: colours.sh must be sourced first for colours to be available
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# ============================================================================
# HEADER FUNCTIONS
# ============================================================================

# Print a styled header box with auto-padding (blue theme)
# Usage: print_header "Title Text" [width]
print_header() {
    local title="$1"
    local width=${2:-68}
    local title_len=${#title}
    local total_padding=$(( width - title_len))
    local left_padding=$(( total_padding / 2 ))
    local right_padding=$(( total_padding - left_padding ))
    
    echo -e "\n${BOLD}${BLUE}╔$(printf '═%.0s' $(seq 1 "$width"))╗${NC}"
    printf '%s%s%s%*s%s%s%s%*s%s%s%s\n' \
        "${BOLD}" "${BLUE}" "║" "$left_padding" "" "${CYAN}" "$title" "${NC}" "$right_padding" "" "${BOLD}" "${BLUE}" "║${NC}"
    echo -e "${BOLD}${BLUE}╚$(printf '═%.0s' $(seq 1 "$width"))╝${NC}\n"
}

# Print a success header box (green theme)
# Usage: print_header_success "Title Text" [width]
print_header_success() {
    local title="$1"
    local width=${2:-60}
    local title_len=${#title}
    local total_padding=$(( width - title_len))
    local left_padding=$(( total_padding / 2 ))
    local right_padding=$(( total_padding - left_padding ))
    
    echo -e "\n${BOLD}${GREEN}╔$(printf '═%.0s' $(seq 1 "$width"))╗${NC}"
    printf '%s%s%s%*s%s%s%s%*s%s%s%s\n' \
        "${BOLD}" "${GREEN}" "║" "$left_padding" "" "${CYAN}" "$title" "${NC}" "$right_padding" "" "${BOLD}" "${GREEN}" "║${NC}"
    echo -e "${BOLD}${GREEN}╚$(printf '═%.0s' $(seq 1 "$width"))╝${NC}\n"
}

# Print a warning header box (yellow theme)
# Usage: print_header_warning "Title Text" [width]
print_header_warning() {
    local title="$1"
    local width=${2:-60}
    local title_len=${#title}
    local total_padding=$(( width - title_len))
    local left_padding=$(( total_padding / 2 ))
    local right_padding=$(( total_padding - left_padding ))
    
    echo -e "\n${BOLD}${YELLOW}╔$(printf '═%.0s' $(seq 1 "$width"))╗${NC}"
    printf '%s%s%s%*s%s%s%s%*s%s%s%s\n' \
        "${BOLD}" "${YELLOW}" "║" "$left_padding" "" "${CYAN}" "$title" "${NC}" "$right_padding" "" "${BOLD}" "${YELLOW}" "║${NC}"
    echo -e "${BOLD}${YELLOW}╚$(printf '═%.0s' $(seq 1 "$width"))╝${NC}\n"
}

# ============================================================================
# MESSAGE FUNCTIONS
# ============================================================================

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

# Print error message (to stderr)
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

# ============================================================================
# FORMATTING FUNCTIONS
# ============================================================================

# Print a separator line
# Usage: print_separator [width]
print_separator() {
    local width=${1:-60}
    echo -e "${BLUE}$(printf '─%.0s' $(seq 1 "$width"))${NC}"
}

# Print a key-value pair
# Usage: print_kv "Key" "Value" [width]
print_kv() {
    local key="$1"
    local value="$2"
    local width=${3:-20}
    printf "${CYAN}%-${width}s${NC} %s\n" "$key:" "$value"
}

# Print a bullet list item
# Usage: print_list_item "Item text"
print_list_item() {
    echo -e "  • ${CYAN}$1${NC}"
}

# Print an indented detail item
# Usage: print_detail "Label" "Value"
print_detail() {
    echo -e "  • ${CYAN}$1:${NC} $2"
}

# Print a menu item (numbered)
# Usage: print_menu_item "1" "Description"
print_menu_item() {
    local number="$1"
    local description="$2"
    echo -e "  ${CYAN}${number})${NC} $description"
}

# Print a simple box around text
# Usage: print_box "text" [colour]
print_box() {
    local text="$1"
    local colour="${2:-$CYAN}"
    local len=${#text}
    local width=$((len + 4))
    
    echo -e "${colour}┌$(printf '─%.0s' $(seq 1 $((width-2))))┐${NC}"
    echo -e "${colour}│${NC} $text ${colour}│${NC}"
    echo -e "${colour}└$(printf '─%.0s' $(seq 1 $((width-2))))┘${NC}"
}

# ============================================================================
# INTERACTIVE FUNCTIONS
# ============================================================================

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

# Read input with a prompt and default value
# Usage: result=$(read_input "Prompt" "default")
read_input() {
    local prompt="$1"
    local default="$2"
    local result
    
    if [[ -n "$default" ]]; then
        read -rp "$prompt [$default]: " result
        echo "${result:-$default}"
    else
        read -rp "$prompt: " result
        echo "$result"
    fi
}

# Show a spinner while a command runs
# Usage: run_with_spinner "command" "message"
run_with_spinner() {
    local cmd="$1"
    local msg="${2:-Working...}"
    local spin='-\|/'
    local i=0
    
    echo -n "$msg "
    eval "$cmd" &
    local pid=$!
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r%s %s" "$msg" "${spin:$i:1}"
        sleep 0.1
    done
    
    wait $pid
    local status=$?
    printf "\r%s " "$msg"
    if [[ $status -eq 0 ]]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
    return $status
}

# ============================================================================
# SUMMARY HELPERS
# ============================================================================

# Print a section header (for summaries)
# Usage: print_section "Section Title"
print_section() {
    echo -e "\n${BOLD}$1${NC}"
}

# Print a quick command hint
# Usage: print_command_hint "description" "command"
print_command_hint() {
    local desc="$1"
    local cmd="$2"
    printf "  ${GREEN}%-25s${NC} - %s\n" "$cmd" "$desc"
}
