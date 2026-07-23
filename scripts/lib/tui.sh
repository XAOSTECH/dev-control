#!/usr/bin/env bash
#
# Dev-Control TUI Library
# Glamorous terminal UI using Charmbracelet Gum with theming support
#
# This library wraps Gum commands with fallback to basic prompts when Gum
# is not available. Supports 3 built-in themes: matrix, hacker, cyber.
#
# Usage:
#   source "$SCRIPT_DIR/lib/tui.sh"
#   tui_set_theme "matrix"  # or "hacker" or "cyber"
#   result=$(tui_input "Enter name")
#   tui_confirm "Continue?" && echo "Yes!"
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# THEME DEFINITIONS
# ============================================================================

# Current theme (default: matrix)
DC_THEME="${DC_THEME:-matrix}"

# Theme: Matrix (green fluorescent glow)
declare -A THEME_MATRIX=(
    [primary]="#00ff00"
    [secondary]="#00cc00"
    [accent]="#39ff14"
    [background]="#0d0d0d"
    [foreground]="#00ff00"
    [border]="#00ff00"
    [cursor]="#39ff14"
    [error]="#ff0000"
    [success]="#00ff00"
    [warning]="#ffff00"
    [info]="#00ffff"
    [prompt_indicator]="▶"
    [cursor_style]="blink"
    [border_style]="rounded"
)

# Theme: Hacker Orange (amber/orange terminal)
declare -A THEME_HACKER=(
    [primary]="#ff8c00"
    [secondary]="#ff6600"
    [accent]="#ffaa00"
    [background]="#1a1100"
    [foreground]="#ff8c00"
    [border]="#ff6600"
    [cursor]="#ffaa00"
    [error]="#ff0000"
    [success]="#00ff00"
    [warning]="#ffff00"
    [info]="#ff8c00"
    [prompt_indicator]="λ"
    [cursor_style]="steady"
    [border_style]="thick"
)

# Theme: Cyber Blue (blue neon)
declare -A THEME_CYBER=(
    [primary]="#00d4ff"
    [secondary]="#0099cc"
    [accent]="#00ffff"
    [background]="#0a0a1a"
    [foreground]="#00d4ff"
    [border]="#00d4ff"
    [cursor]="#00ffff"
    [error]="#ff0055"
    [success]="#00ff88"
    [warning]="#ffcc00"
    [info]="#00d4ff"
    [prompt_indicator]="⟩"
    [cursor_style]="blink"
    [border_style]="double"
)

# Current active theme colours (populated by tui_set_theme)
declare -A CURRENT_THEME

# ============================================================================
# GUM DETECTION
# ============================================================================

GUM_AVAILABLE=false

# Check if Gum is installed
check_gum() {
    if command -v gum &>/dev/null; then
        GUM_AVAILABLE=true
        return 0
    else
        GUM_AVAILABLE=false
        return 1
    fi
}

# Install Gum if not present (optional, prompts user)
install_gum() {
    if check_gum; then
        return 0
    fi
    
    echo "Gum is not installed. It provides beautiful terminal UI."
    echo ""
    echo "Install options:"
    echo "  brew install gum          # macOS/Homebrew"
    echo "  sudo snap install gum     # Ubuntu/Snap"
    echo "  go install github.com/charmbracelet/gum@latest  # Go"
    echo ""
    
    read -rp "Would you like to install Gum now? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy] ]]; then
        if command -v brew &>/dev/null; then
            brew install gum && GUM_AVAILABLE=true
        elif command -v snap &>/dev/null; then
            sudo snap install gum && GUM_AVAILABLE=true
        elif command -v go &>/dev/null; then
            go install github.com/charmbracelet/gum@latest && GUM_AVAILABLE=true
        else
            echo "Could not auto-install. Please install manually."
            return 1
        fi
    fi
}

# ============================================================================
# THEME MANAGEMENT
# ============================================================================

# Set the active theme
# Usage: tui_set_theme "matrix" | "hacker" | "cyber"
tui_set_theme() {
    local theme_name="${1:-matrix}"
    DC_THEME="$theme_name"
    
    case "$theme_name" in
        matrix)
            for key in "${!THEME_MATRIX[@]}"; do
                CURRENT_THEME[$key]="${THEME_MATRIX[$key]}"
            done
            ;;
        hacker)
            for key in "${!THEME_HACKER[@]}"; do
                CURRENT_THEME[$key]="${THEME_HACKER[$key]}"
            done
            ;;
        cyber)
            for key in "${!THEME_CYBER[@]}"; do
                CURRENT_THEME[$key]="${THEME_CYBER[$key]}"
            done
            ;;
        *)
            # Default to matrix
            for key in "${!THEME_MATRIX[@]}"; do
                CURRENT_THEME[$key]="${THEME_MATRIX[$key]}"
            done
            ;;
    esac
    
    # Export Gum environment variables
    export GUM_INPUT_PROMPT_FOREGROUND="${CURRENT_THEME[primary]}"
    export GUM_INPUT_CURSOR_FOREGROUND="${CURRENT_THEME[cursor]}"
    export GUM_CONFIRM_PROMPT_FOREGROUND="${CURRENT_THEME[primary]}"
    export GUM_CONFIRM_SELECTED_FOREGROUND="${CURRENT_THEME[accent]}"
    export GUM_CHOOSE_CURSOR_FOREGROUND="${CURRENT_THEME[accent]}"
    export GUM_CHOOSE_SELECTED_FOREGROUND="${CURRENT_THEME[primary]}"
    export GUM_SPIN_SPINNER_FOREGROUND="${CURRENT_THEME[accent]}"
    export GUM_STYLE_FOREGROUND="${CURRENT_THEME[foreground]}"
    export GUM_STYLE_BORDER_FOREGROUND="${CURRENT_THEME[border]}"
}

# Get current theme name
tui_get_theme() {
    echo "$DC_THEME"
}

# List available themes
tui_list_themes() {
    echo "matrix hacker cyber"
}

# Interactive theme selector
tui_choose_theme() {
    local choice
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        choice=$(gum choose "matrix" "hacker" "cyber" \
            --header "Select Theme:" \
            --cursor "${CURRENT_THEME[prompt_indicator]} " \
            --cursor.foreground "${CURRENT_THEME[accent]}")
    else
        echo "Available themes: matrix, hacker, cyber"
        read -rp "Choose theme: " choice
    fi
    
    if [[ -n "$choice" ]]; then
        tui_set_theme "$choice"
        echo "$choice"
    fi
}

# ============================================================================
# INPUT FUNCTIONS (with fallbacks)
# ============================================================================

# Styled text input
# Usage: result=$(tui_input "Prompt text" "default value" "placeholder")
tui_input() {
    local prompt="${1:-Enter value}"
    local default="${2:-}"
    local placeholder="${3:-Type here...}"
    
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        gum input \
            --prompt "${CURRENT_THEME[prompt_indicator]} $prompt: " \
            --placeholder "$placeholder" \
            --value "$default" \
            --cursor.foreground "${CURRENT_THEME[cursor]}" \
            --prompt.foreground "${CURRENT_THEME[primary]}"
    else
        local result
        if [[ -n "$default" ]]; then
            read -rp "$prompt [$default]: " result
            echo "${result:-$default}"
        else
            read -rp "$prompt: " result
            echo "$result"
        fi
    fi
}

# Password/secret input (masked)
# Usage: secret=$(tui_password "Enter password")
tui_password() {
    local prompt="${1:-Password}"
    
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        gum input \
            --password \
            --prompt "${CURRENT_THEME[prompt_indicator]} $prompt: " \
            --cursor.foreground "${CURRENT_THEME[cursor]}" \
            --prompt.foreground "${CURRENT_THEME[primary]}"
    else
        read -rsp "$prompt: " result
        echo ""
        echo "$result"
    fi
}

# Confirmation prompt
# Usage: tui_confirm "Are you sure?" && echo "Confirmed"
tui_confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-no}"  # yes or no
    
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        local affirmative="Yes"
        local negative="No"
        [[ "$default" == "yes" ]] && gum confirm "$prompt" --default=true \
            --prompt.foreground "${CURRENT_THEME[primary]}" \
            --selected.foreground "${CURRENT_THEME[accent]}"
        [[ "$default" != "yes" ]] && gum confirm "$prompt" --default=false \
            --prompt.foreground "${CURRENT_THEME[primary]}" \
            --selected.foreground "${CURRENT_THEME[accent]}"
    else
        local yn_prompt="[y/N]"
        [[ "$default" == "yes" ]] && yn_prompt="[Y/n]"
        
        read -rp "$prompt $yn_prompt: " response
        if [[ "$default" == "yes" ]]; then
            [[ ! "$response" =~ ^[Nn] ]]
        else
            [[ "$response" =~ ^[Yy] ]]
        fi
    fi
}

# Single choice selection
# Usage: choice=$(tui_choose "Option 1" "Option 2" "Option 3")
tui_choose() {
    local header="${1:-}"
    shift
    local options=("$@")
    
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        if [[ -n "$header" ]]; then
            printf '%s\n' "${options[@]}" | gum choose \
                --header "$header" \
                --cursor "${CURRENT_THEME[prompt_indicator]} " \
                --cursor.foreground "${CURRENT_THEME[accent]}" \
                --selected.foreground "${CURRENT_THEME[primary]}"
        else
            printf '%s\n' "${options[@]}" | gum choose \
                --cursor "${CURRENT_THEME[prompt_indicator]} " \
                --cursor.foreground "${CURRENT_THEME[accent]}" \
                --selected.foreground "${CURRENT_THEME[primary]}"
        fi
    else
        local i=1
        [[ -n "$header" ]] && echo "$header"
        for opt in "${options[@]}"; do
            echo "  $i) $opt"
            ((i++))
        done
        read -rp "Select [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[$((choice-1))]}"
        fi
    fi
}

# Multi-select (checkboxes)
# Usage: choices=$(tui_multiselect "header" "opt1" "opt2" "opt3")
tui_multiselect() {
    local header="${1:-}"
    shift
    local options=("$@")
    
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        if [[ -n "$header" ]]; then
            printf '%s\n' "${options[@]}" | gum choose --no-limit \
                --header "$header" \
                --cursor "${CURRENT_THEME[prompt_indicator]} " \
                --cursor.foreground "${CURRENT_THEME[accent]}" \
                --selected.foreground "${CURRENT_THEME[primary]}"
        else
            printf '%s\n' "${options[@]}" | gum choose --no-limit \
                --cursor "${CURRENT_THEME[prompt_indicator]} " \
                --cursor.foreground "${CURRENT_THEME[accent]}" \
                --selected.foreground "${CURRENT_THEME[primary]}"
        fi
    else
        echo "$header (enter numbers separated by spaces):"
        local i=1
        for opt in "${options[@]}"; do
            echo "  $i) $opt"
            ((i++))
        done
        read -rp "Select: " selections
        for sel in $selections; do
            if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#options[@]} )); then
                echo "${options[$((sel-1))]}"
            fi
        done
    fi
}

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

# Styled echo with theme colours
# Usage: tui_echo "Message" "style"  # style: info, success, error, warning, primary
tui_echo() {
    local message="$1"
    local style="${2:-primary}"
    
    local colour="${CURRENT_THEME[$style]}"
    [[ -z "$colour" ]] && colour="${CURRENT_THEME[foreground]}"
    
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        gum style --foreground "$colour" "$message"
    else
        echo "$message"
    fi
}

# Styled box/panel
# Usage: tui_box "Title" "Content line 1" "Content line 2"
tui_box() {
    local title="$1"
    shift
    local content="$*"
    
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        echo "$content" | gum style \
            --border "${CURRENT_THEME[border_style]}" \
            --border-foreground "${CURRENT_THEME[border]}" \
            --padding "1 2" \
            --margin "1" \
            --bold \
            --foreground "${CURRENT_THEME[primary]}"
    else
        echo "┌─ $title ─┐"
        echo "$content" | sed 's/^/│ /'
        echo "└──────────┘"
    fi
}

# Spinner for long operations
# Usage: tui_spin "Loading..." -- long_running_command
tui_spin() {
    local title="$1"
    shift
    
    if [[ "$GUM_AVAILABLE" == "true" && "$1" == "--" ]]; then
        shift
        gum spin \
            --spinner dot \
            --title "$title" \
            --spinner.foreground "${CURRENT_THEME[accent]}" \
            -- "$@"
    else
        echo "$title"
        "$@"
    fi
}

# Progress indicator (manual update)
# Usage: for i in {1..100}; do tui_progress $i 100 "Processing"; sleep 0.1; done
tui_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-Progress}"
    local percent=$((current * 100 / total))
    local bar_width=40
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))
    
    printf "\r%s [" "$message"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percent"
    
    [[ $current -eq $total ]] && echo ""
}

# ============================================================================
# BANNER / HEADER
# ============================================================================

# Display themed banner
# Usage: tui_banner "App Name" "v1.0.0"
tui_banner() {
    local title="$1"
    local subtitle="${2:-}"
    
    if [[ "$GUM_AVAILABLE" == "true" ]]; then
        local banner_text="$title"
        [[ -n "$subtitle" ]] && banner_text="$title\n$subtitle"
        
        echo -e "$banner_text" | gum style \
            --border "${CURRENT_THEME[border_style]}" \
            --border-foreground "${CURRENT_THEME[border]}" \
            --foreground "${CURRENT_THEME[primary]}" \
            --bold \
            --align center \
            --width 60 \
            --padding "1 4"
    else
        local width=60
        local border_char="═"
        local top_border=$(printf "%${width}s" | tr ' ' "$border_char")
        
        echo "╔${top_border}╗"
        printf "║%*s%s%*s║\n" $(( (width - ${#title}) / 2 )) "" "$title" $(( (width - ${#title} + 1) / 2 )) ""
        if [[ -n "$subtitle" ]]; then
            printf "║%*s%s%*s║\n" $(( (width - ${#subtitle}) / 2 )) "" "$subtitle" $(( (width - ${#subtitle} + 1) / 2 )) ""
        fi
        echo "╚${top_border}╝"
    fi
}

# ============================================================================
# INITIALISATION
# ============================================================================

# Auto-initialise on source (use || true to prevent set -e from exiting)
check_gum || true
tui_set_theme "${DC_THEME:-matrix}"
