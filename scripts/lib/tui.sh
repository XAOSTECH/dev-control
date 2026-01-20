#!/usr/bin/env bash
#
# Dev-Control Shared Library: TUI (Terminal UI)
# Rich interactive terminal UI using gum/fzf with fallbacks
#
# Features:
#   - Auto-detect gum/fzf availability
#   - Graceful fallback to basic bash prompts
#   - Consistent styling across all tools
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# ============================================================================
# DETECTION
# ============================================================================

# Detect available TUI tools
detect_tui_tool() {
    if command -v gum &>/dev/null; then
        echo "gum"
    elif command -v fzf &>/dev/null; then
        echo "fzf"
    else
        echo "bash"
    fi
}

TUI_TOOL="$(detect_tui_tool)"

# Check if rich TUI is available
has_rich_tui() {
    [[ "$TUI_TOOL" == "gum" || "$TUI_TOOL" == "fzf" ]]
}

# ============================================================================
# SELECTION (Choose from list)
# ============================================================================

# Interactive selection from options
# Usage: choice=$(tui_choose "Select option:" "opt1" "opt2" "opt3")
tui_choose() {
    local prompt="$1"
    shift
    local options=("$@")
    
    case "$TUI_TOOL" in
        gum)
            gum choose --header="$prompt" "${options[@]}"
            ;;
        fzf)
            printf '%s\n' "${options[@]}" | fzf --prompt="$prompt "
            ;;
        *)
            # Bash fallback
            echo "$prompt" >&2
            local i=1
            for opt in "${options[@]}"; do
                echo "  $i) $opt" >&2
                ((i++))
            done
            read -rp "> " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
                echo "${options[$((choice-1))]}"
            else
                echo "$choice"
            fi
            ;;
    esac
}

# Multi-select from options
# Usage: choices=$(tui_multi_choose "Select options:" "opt1" "opt2" "opt3")
tui_multi_choose() {
    local prompt="$1"
    shift
    local options=("$@")
    
    case "$TUI_TOOL" in
        gum)
            gum choose --no-limit --header="$prompt" "${options[@]}"
            ;;
        fzf)
            printf '%s\n' "${options[@]}" | fzf --multi --prompt="$prompt "
            ;;
        *)
            # Bash fallback
            echo "$prompt (comma-separated numbers or 'all'):" >&2
            local i=1
            for opt in "${options[@]}"; do
                echo "  $i) $opt" >&2
                ((i++))
            done
            read -rp "> " selection
            
            if [[ "$selection" == "all" ]]; then
                printf '%s\n' "${options[@]}"
            else
                IFS=',' read -ra indices <<< "$selection"
                for idx in "${indices[@]}"; do
                    idx=$(echo "$idx" | tr -d ' ')
                    [[ "$idx" =~ ^[0-9]+$ ]] && echo "${options[$((idx-1))]}"
                done
            fi
            ;;
    esac
}

# ============================================================================
# INPUT
# ============================================================================

# Text input with prompt
# Usage: value=$(tui_input "Enter name:" "default")
tui_input() {
    local prompt="$1"
    local default="${2:-}"
    local placeholder="${3:-}"
    
    case "$TUI_TOOL" in
        gum)
            if [[ -n "$default" ]]; then
                gum input --placeholder="$placeholder" --value="$default" --header="$prompt"
            else
                gum input --placeholder="${placeholder:-Type here...}" --header="$prompt"
            fi
            ;;
        *)
            # Bash/fzf fallback
            if [[ -n "$default" ]]; then
                read -rp "$prompt [$default]: " value
                echo "${value:-$default}"
            else
                read -rp "$prompt: " value
                echo "$value"
            fi
            ;;
    esac
}

# Multi-line text input
# Usage: text=$(tui_write "Enter description:")
tui_write() {
    local prompt="$1"
    local default="${2:-}"
    
    case "$TUI_TOOL" in
        gum)
            gum write --header="$prompt" --value="$default"
            ;;
        *)
            echo "$prompt (enter empty line to finish):" >&2
            local text=""
            while IFS= read -r line; do
                [[ -z "$line" ]] && break
                text+="$line"$'\n'
            done
            echo "$text"
            ;;
    esac
}

# Password input (hidden)
# Usage: password=$(tui_password "Enter token:")
tui_password() {
    local prompt="$1"
    
    case "$TUI_TOOL" in
        gum)
            gum input --password --header="$prompt"
            ;;
        *)
            read -rsp "$prompt: " value
            echo >&2
            echo "$value"
            ;;
    esac
}

# ============================================================================
# CONFIRMATION
# ============================================================================

# Yes/No confirmation
# Usage: if tui_confirm "Proceed?"; then ...
tui_confirm() {
    local prompt="$1"
    local default="${2:-no}"
    
    case "$TUI_TOOL" in
        gum)
            if [[ "$default" == "yes" ]]; then
                gum confirm --default=yes "$prompt"
            else
                gum confirm "$prompt"
            fi
            ;;
        *)
            local yn="[y/N]"
            [[ "$default" == "yes" ]] && yn="[Y/n]"
            read -rp "$prompt $yn: " response
            if [[ "$default" == "yes" ]]; then
                [[ ! "$response" =~ ^[Nn] ]]
            else
                [[ "$response" =~ ^[Yy] ]]
            fi
            ;;
    esac
}

# ============================================================================
# DISPLAY
# ============================================================================

# Styled header
tui_header() {
    local text="$1"
    
    case "$TUI_TOOL" in
        gum)
            gum style --border double --align center --width 60 --margin "1 2" --padding "1 4" "$text"
            ;;
        *)
            print_header "$text"
            ;;
    esac
}

# Spinner while command runs
# Usage: tui_spin "Loading..." "sleep 2"
tui_spin() {
    local title="$1"
    local command="$2"
    
    case "$TUI_TOOL" in
        gum)
            gum spin --spinner dot --title "$title" -- bash -c "$command"
            ;;
        *)
            echo -n "$title..." >&2
            eval "$command"
            echo " done" >&2
            ;;
    esac
}

# Format text with style
# Usage: tui_format "bold" "text"
tui_format() {
    local style="$1"
    local text="$2"
    
    case "$TUI_TOOL" in
        gum)
            case "$style" in
                bold) gum style --bold "$text" ;;
                dim) gum style --faint "$text" ;;
                italic) gum style --italic "$text" ;;
                underline) gum style --underline "$text" ;;
                code) gum style --background 240 --foreground 255 --padding "0 1" "$text" ;;
                *) echo "$text" ;;
            esac
            ;;
        *)
            case "$style" in
                bold) echo -e "${BOLD}${text}${NC}" ;;
                dim) echo -e "${DIM}${text}${NC}" ;;
                *) echo "$text" ;;
            esac
            ;;
    esac
}

# ============================================================================
# FILE SELECTION
# ============================================================================

# File picker
# Usage: file=$(tui_file_picker "/path" "*.sh")
tui_file_picker() {
    local dir="${1:-.}"
    local pattern="${2:-*}"
    
    case "$TUI_TOOL" in
        gum)
            gum file "$dir"
            ;;
        fzf)
            find "$dir" -name "$pattern" -type f 2>/dev/null | fzf
            ;;
        *)
            echo "Enter file path:" >&2
            read -rp "> " file
            echo "$file"
            ;;
    esac
}

# Directory picker
# Usage: dir=$(tui_dir_picker "/path")
tui_dir_picker() {
    local start="${1:-.}"
    
    case "$TUI_TOOL" in
        gum)
            gum file --directory "$start"
            ;;
        fzf)
            find "$start" -type d 2>/dev/null | fzf
            ;;
        *)
            echo "Enter directory path:" >&2
            read -rp "> " dir
            echo "$dir"
            ;;
    esac
}

# ============================================================================
# TABLES
# ============================================================================

# Display data as table
# Usage: tui_table "Header1,Header2" "row1col1,row1col2" "row2col1,row2col2"
tui_table() {
    local header="$1"
    shift
    local rows=("$@")
    
    case "$TUI_TOOL" in
        gum)
            {
                echo "$header"
                for row in "${rows[@]}"; do
                    echo "$row"
                done
            } | gum table --border normal
            ;;
        *)
            # Simple bash table
            IFS=',' read -ra cols <<< "$header"
            printf '%-20s' "${cols[@]}"
            echo
            printf '%.0s-' {1..60}
            echo
            for row in "${rows[@]}"; do
                IFS=',' read -ra cols <<< "$row"
                printf '%-20s' "${cols[@]}"
                echo
            done
            ;;
    esac
}
