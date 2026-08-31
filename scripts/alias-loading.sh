#!/usr/bin/env bash
#
# Dev-Control Alias Loading Script
# Interactive alias installer with dynamic path resolution
# 
# Generates shell-specific alias files (.bash_aliases, .zsh_aliases, or fish conf.d)
# and wires them into the appropriate shell RC file.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/colours.sh"
source "$SCRIPT_DIR/lib/print.sh"

# Configuration - paths derived from the active shell
BASHRC_MODIFIED="false"
case "$(basename "${SHELL:-bash}")" in
    zsh)
        SHELL_TYPE="zsh"
        BASH_ALIASES="$HOME/.zsh_aliases"
        BASHRC="$HOME/.zshrc"
        BACKUP_DIR="$HOME/.zsh_backups"
        ;;
    fish)
        SHELL_TYPE="fish"
        BASH_ALIASES="$HOME/.config/fish/conf.d/dc-aliases.fish"
        BASHRC=""
        BACKUP_DIR="$HOME/.config/fish/backups"
        ;;
    *)
        SHELL_TYPE="bash"
        BASH_ALIASES="$HOME/.bash_aliases"
        BASHRC="$HOME/.bashrc"
        BACKUP_DIR="$HOME/.bash_backups"
        ;;
esac

# ============================================================================
# ALIAS ARRAYS - Complete alias definitions by category
# ============================================================================

# Dev-Control specific shortcuts
declare -a DC_ALIASES=(
    "# Dev-Control shortcuts"
    "alias dc-control='${SCRIPT_DIR}/dev-control.sh'"
    "alias dc='${SCRIPT_DIR}/dev-control.sh'"
    "alias dc-git='${SCRIPT_DIR}/git-control.sh'"
    "alias dc-init='${SCRIPT_DIR}/template-loading.sh'"
    "alias dc-contain='${SCRIPT_DIR}/containerise.sh'"
    "alias dc-create='${SCRIPT_DIR}/create-repo.sh'"
    "alias dc-repo='${SCRIPT_DIR}/create-repo.sh'"
    "alias dc-pr='${SCRIPT_DIR}/create-pr.sh'"
    "alias dc-mcp='${SCRIPT_DIR}/mcp-setup.sh'"
    "alias dc-modules='${SCRIPT_DIR}/module-nesting.sh'"
    "alias dc-fix='${SCRIPT_DIR}/fix-history.sh'"
    "alias dc-alias='${SCRIPT_DIR}/alias-loading.sh'"
    "alias dc-aliases='${SCRIPT_DIR}/alias-loading.sh'"
    "alias dc-licences='${SCRIPT_DIR}/licences.sh'"
    "alias dc-lic='${SCRIPT_DIR}/licences.sh'"
    "alias dc-pkg='${SCRIPT_DIR}/packaging.sh'"
    "alias dc-cluster='${SCRIPT_DIR}/dev-control.sh cluster'"
    "alias dc-gpg='source ${SCRIPT_DIR}/lib/git/gpg.sh && setup_bot_gpg_for_repo'"
    "alias dca-alias='${SCRIPT_DIR}/alias-loading.sh <<< A && source ${BASHRC} && echo -e \"\033[1mChanges applied!\033[0m\"'"
    "alias dc-help='echo \"dc-control: Main menu for all Dev-Control tools\"; echo \"dc-git: Unified git services menu\"; echo \"dc-init: Initialise repo with templates\"; echo \"dc-repo: Create GitHub repo from current folder\"; echo \"dc-pr: Create pull request from current branch\"; echo \"dc-modules: Manage git submodules\"; echo \"dc-licences: Detect and audit licences\"; echo \"dc-fix: Fix commit history interactively\"; echo \"dc-pkg: Build multi-platform packages\"; echo \"dc-cluster: Setup fully fledged development environment\"; echo \"dc-gpg-setup: Setup GPG bot for GitHub Actions\"; echo \"dc-aliases: Reload alias installer\"'"
)

# Git shortcuts
declare -a GIT_ALIASES=(
    "# Git shortcuts"
    "alias gst='git status'"
    "alias ga='git add'"
    "alias gaa='git add .'"
    "alias gcm='git commit -m'"
    "alias gca='git add . && git commit --amend --no-edit && git push --force-with-lease origin HEAD'"
    'gcda() { git add . "$@"; author_date=$(git show -s --format=%aD HEAD); GIT_COMMITTER_DATE="$author_date" git commit --amend --no-edit --date="$author_date"; git push --force-with-lease origin HEAD; }'
    "alias gp='git push'"
    "alias gpf='git push --force-with-lease'"
    "alias gpl='git pull'"
    "alias gf='git fetch --all --prune'"
    "alias gl='git log --oneline --graph --decorate --all'"
    "alias gls='git log --oneline -10'"
    "alias gd='git diff'"
    "alias gds='git diff --staged'"
    "alias gco='git checkout'"
    "alias gcob='git checkout -b'"
    "alias gb='git branch'"
    "alias gba='git branch -a'"
    "alias gbd='git branch -d'"
    "alias gbD='git branch -D'"
    "alias gm='git merge'"
    "alias gr='git rebase'"
    "alias gri='git rebase -i'"
    "alias gstash='git stash'"
    "alias gstp='git stash pop'"
    "alias gstl='git stash list'"
    "alias gcl='git clone'"
    "alias grv='git remote -v'"
    "alias gundo='git reset HEAD~1 --soft'"
    "alias gwip='git add . && git commit -m \"WIP\"'"
)

# Safety net aliases
declare -a SAFE_ALIASES=(
    "# Safety nets - prevent accidental data loss"
    "alias rm='rm -i'"
    "alias cp='cp -i'"
    "alias mv='mv -i'"
    "alias mkdir='mkdir -pv'"
    "alias ln='ln -i'"
    "alias chown='chown --preserve-root'"
    "alias chmod='chmod --preserve-root'"
    "alias chgrp='chgrp --preserve-root'"
)

# System aliases
declare -a SYSMON_ALIASES=(
    "# System monitoring/operations"
    "alias reboot='sudo systemctl -i reboot' 'rb!'='sudo systemctl -i reboot'"
    "#alias suspend='sudo systemctl -i suspend' 'sp!'='sudo systemctl -i suspend'"
    "#alias 'sp-to-hi!'='sudo systemctl -i suspend-then-hibernate' 's2h!'='sudo systemctl -i suspend-then-hibernate' 'sth!'='sudo systemctl -i suspend-then-hibernate'"
    "#alias hibernate='sudo systemctl -i hibernate' 'hi!'='sudo systemctl -i hibernate' 'bye!'='sudo systemctl -i hibernate'"
    "alias ports='netstat -tulanp 2>/dev/null || ss -tulanp'"
    "alias meminfo='free -h'"
    "alias cpuinfo='lscpu'"
    "alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'"
    "alias psmem='ps auxf | sort -nr -k 4 | head -10'"
    "alias pscpu='ps auxf | sort -nr -k 3 | head -10'"
    "alias disk='df -h | grep -E \"^/dev|Filesystem\"'"
    "alias diskuse='du -sh * 2>/dev/null | sort -h'"
    "alias top10='du -hsx * 2>/dev/null | sort -rh | head -10'"
    "alias temp='sensors 2>/dev/null || echo \"lm-sensors not installed\"'"
    "alias watch='watch -n 1'"
    "alias fullscan='sudo find / -mindepth 1 \\( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /snap -o -path /var/lib/flatpak -o -path */.steam/steam/steamapps -o -path */SteamLibrary \\) -prune -o -type f -print0 2>/dev/null | xargs -0 -P 16 -n 100 clamdscan --fdpass  2>&1 | tee \"/tmp/terminal_fullscan_\$(date +%Y%m%d_%H%M%S).log\"'"
    "alias gst='env GSK_RENDERER=gl showtime'"
)

# Directory operation aliases
declare -a DIR_ALIASES=(
    "# Directory operations"
    "alias md='mkdir -p'"
    "alias rd='rmdir'"
    "alias ..='cd ..'"
    "alias ...='cd ../..'"
    "alias ....='cd ../../..'"
    "alias .....='cd ../../../..'"
    "alias ~='cd ~'"
    "alias ll='ls -alFh'"
    "alias la='ls -A'"
    "alias l='ls -CF'"
    "alias lt='ls -alFht'"
    "alias lS='ls -alFhS'"
    "alias tree='tree -C'"
    "alias tree2='tree -C -L 2'"
    "alias tree3='tree -C -L 3'"
)

# Network utility aliases
declare -a NET_ALIASES=(
    "# Network utilities"
    "alias upd='sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean && sudo snap refresh'"
    "alias lpp='sudo pro disable livepatch && sudo pro enable livepatch && upd'"
    "alias myip='curl -s ifconfig.me && echo'"
    "alias myip6='curl -s ifconfig.me/ip6 && echo'"
    "alias localip='hostname -I | awk \"{print \\\$1}\"'"
    "alias ping='ping -c 5'"
    "alias fastping='ping -c 100 -i 0.2'"
    "alias listening='lsof -i -P -n | grep LISTEN'"
    "alias connections='netstat -an | grep ESTABLISHED'"
    "alias wget='wget -c'"
    "alias header='curl -I'"
    "alias dns='dig +short'"
)

# Container (Docker/Podman) aliases
declare -a CONTAINER_ALIASES=(
    "# Docker/Podman shortcuts"
    "alias dps='docker ps 2>/dev/null || podman ps'"
    "alias dpsa='docker ps -a 2>/dev/null || podman ps -a'"
    "alias di='docker images 2>/dev/null || podman images'"
    "alias drm='docker rm 2>/dev/null || podman rm'"
    "alias drmi='docker rmi 2>/dev/null || podman rmi'"
    "alias dex='docker exec -it'"
    "alias dlogs='docker logs -f'"
    "alias dprune='docker system prune -af 2>/dev/null || podman system prune -af'"
    "alias dstop='docker stop \$(docker ps -q) 2>/dev/null'"
    "alias dcomp='docker-compose'"
    "alias dcu='docker-compose up -d'"
    "alias dcd='docker-compose down'"
    "alias dcl='docker-compose logs -f'"
    "alias dcb='docker-compose build'"
)

# Quick edit aliases
declare -a EDIT_ALIASES=(
    "# Quick edits and shell utilities"
    "alias bashrc='nano ~/.bashrc'"
    "alias aliases='nano ~/.bash_aliases'"
    "alias reload='source ~/.bashrc && echo \"Bash config reloaded!\"'"
    "alias path='echo -e \"\${PATH//:/\\n}\"'"
    "alias now='date +\"%Y-%m-%d %H:%M:%S\"'"
    "alias week='date +%V'"
    "alias h='history'"
    "alias hg='history | grep'"
    "alias cls='clear'"
    "alias c='clear'"
    "alias x='exit'"
    "alias q='exit'"
)

# Archive/compression aliases
declare -a ARCHIVE_ALIASES=(
    "# Archive and compression"
    "alias untar='tar -xvf'"
    "alias untargz='tar -xzf'"
    "alias untarbz='tar -xjf'"
    "alias mktar='tar -cvf'"
    "alias mktargz='tar -czvf'"
    "alias mktarbz='tar -cjvf'"
    "alias zip='zip -r'"
)

# Search and find aliases
declare -a SEARCH_ALIASES=(
    "# Search and find utilities"
    "alias ff='find . -type f -name'"
    "alias fd='find . -type d -name'"
    "alias grep='grep --color=auto'"
    "alias egrep='egrep --color=auto'"
    "alias fgrep='fgrep --color=auto'"
    "alias rg='rg --smart-case'"
    "alias ag='ag --smart-case'"
)

# Fish-specific overrides for entries that differ in syntax
declare -a DC_ALIASES_FISH=(
    "# Dev-Control shortcuts"
    "alias dc-control '${SCRIPT_DIR}/dev-control.sh'"
    "alias dc '${SCRIPT_DIR}/dev-control.sh'"
    "alias dc-git '${SCRIPT_DIR}/git-control.sh'"
    "alias dc-init '${SCRIPT_DIR}/template-loading.sh'"
    "alias dc-contain '${SCRIPT_DIR}/containerise.sh'"
    "alias dc-create '${SCRIPT_DIR}/create-repo.sh'"
    "alias dc-repo '${SCRIPT_DIR}/create-repo.sh'"
    "alias dc-pr '${SCRIPT_DIR}/create-pr.sh'"
    "alias dc-mcp '${SCRIPT_DIR}/mcp-setup.sh'"
    "alias dc-modules '${SCRIPT_DIR}/module-nesting.sh'"
    "alias dc-fix '${SCRIPT_DIR}/fix-history.sh'"
    "alias dc-alias '${SCRIPT_DIR}/alias-loading.sh'"
    "alias dc-aliases '${SCRIPT_DIR}/alias-loading.sh'"
    "alias dc-licences '${SCRIPT_DIR}/licences.sh'"
    "alias dc-lic '${SCRIPT_DIR}/licences.sh'"
    "alias dc-pkg '${SCRIPT_DIR}/packaging.sh'"
    "alias dc-cluster '${SCRIPT_DIR}/dev-control.sh cluster'"
    "alias dc-gpg 'source ${SCRIPT_DIR}/lib/git/gpg.sh; setup_bot_gpg_for_repo'"
    "function dca-alias"
    "    ${SCRIPT_DIR}/alias-loading.sh <<< A"
    "    source ~/.config/fish/conf.d/dc-aliases.fish"
    "    echo (set_color --bold)'Changes applied!'(set_color normal)"
    "end"
    "function dc-help"
    "    echo 'dc-control: Main menu for all Dev-Control tools'"
    "    echo 'dc-git: Unified git services menu'"
    "    echo 'dc-init: Initialise repo with templates'"
    "    echo 'dc-repo: Create GitHub repo from current folder'"
    "    echo 'dc-pr: Create pull request from current branch'"
    "    echo 'dc-modules: Manage git submodules'"
    "    echo 'dc-licences: Detect and audit licences'"
    "    echo 'dc-fix: Fix commit history interactively'"
    "    echo 'dc-pkg: Build multi-platform packages'"
    "    echo 'dc-cluster: Setup fully fledged development environment'"
    "    echo 'dc-aliases: Reload alias installer'"
    "end"
)

# Fish-specific git aliases (gcda requires fish function syntax)
declare -a GIT_ALIASES_FISH=(
    "# Git shortcuts"
    "alias gst 'git status'"
    "alias ga 'git add'"
    "alias gaa 'git add .'"
    "alias gcm 'git commit -m'"
    "alias gca 'git add .; and git commit --amend --no-edit; and git push --force-with-lease origin HEAD'"
    "function gcda"
    "    git add . \$argv"
    "    set author_date (git show -s --format=%aD HEAD)"
    "    set -x GIT_COMMITTER_DATE \$author_date"
    "    git commit --amend --no-edit --date=\$author_date"
    "    git push --force-with-lease origin HEAD"
    "end"
    "alias gp 'git push'"
    "alias gpf 'git push --force-with-lease'"
    "alias gpl 'git pull'"
    "alias gf 'git fetch --all --prune'"
    "alias gl 'git log --oneline --graph --decorate --all'"
    "alias gls 'git log --oneline -10'"
    "alias gd 'git diff'"
    "alias gds 'git diff --staged'"
    "alias gco 'git checkout'"
    "alias gcob 'git checkout -b'"
    "alias gb 'git branch'"
    "alias gba 'git branch -a'"
    "alias gbd 'git branch -d'"
    "alias gbD 'git branch -D'"
    "alias gm 'git merge'"
    "alias gr 'git rebase'"
    "alias gri 'git rebase -i'"
    "alias gstash 'git stash'"
    "alias gstp 'git stash pop'"
    "alias gstl 'git stash list'"
    "alias gcl 'git clone'"
    "alias grv 'git remote -v'"
    "alias gundo 'git reset HEAD~1 --soft'"
    "alias gwip 'git add .; and git commit -m WIP'"
)

# Fish-specific quick-edit aliases (shell-appropriate config paths)
declare -a EDIT_ALIASES_FISH=(
    "# Quick edits and shell utilities"
    "alias bashrc 'nano ~/.config/fish/config.fish'"
    "alias aliases 'nano ~/.config/fish/conf.d/dc-aliases.fish'"
    "alias reload 'exec fish'"
    "alias path 'echo \$PATH | string split :'"
    "alias now 'date +\"%Y-%m-%d %H:%M:%S\"'"
    "alias week 'date +%V'"
    "alias h 'history'"
    "alias hg 'history | grep'"
    "alias cls 'clear'"
    "alias c 'clear'"
    "alias x 'exit'"
    "alias q 'exit'"
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

create_backup() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        local backup_name="$(basename "$file").$(date +%Y%m%d_%H%M%S).bak"
        cp "$file" "$BACKUP_DIR/$backup_name"
        print_info "Created backup: $BACKUP_DIR/$backup_name"
    fi
}

# ============================================================================
# MAIN FUNCTIONS
# ============================================================================

display_menu() {
    print_section "Shell: ${SHELL_TYPE} → $(basename "$BASH_ALIASES")"
    print_section "Select alias categories to install:"
    
    print_menu_item "1" "Dev-Control Commands  - dc-init, dc-modules, dc-licences..."
    print_menu_item "2" "Git Shortcuts         - gst, ga, gcm, gp, gl, gco, gb..."
    print_menu_item "3" "Safety Nets           - rm -i, cp -i, mv -i..."
    print_menu_item "4" "System Monitoring     - ports, meminfo, disk, psg..."
    print_menu_item "5" "Directory Operations  - md, rd, ll, la, .., ...."
    print_menu_item "6" "Network Utilities     - myip, ping, listening..."
    print_menu_item "7" "Container Shortcuts   - dps, di, drm, dc, dcu..."
    print_menu_item "8" "Quick Edits           - bashrc, reload, path, now..."
    print_menu_item "9" "Archive/Compression   - untar, mktar, zip..."
    print_menu_item "10" "Search Utilities     - ff, fd, grep..."
    echo ""
    echo -e "  ${GREEN}A)${NC} Install ALL categories"
    echo -e "  ${YELLOW}Q)${NC} Quit without installing"
    echo ""
}

get_selection() {
    local selection
    echo -e "${BOLD}Enter your choices (comma-separated, e.g., 1,2,3 or A for all):${NC}" >&2
    read -rp "> " selection
    echo "$selection"
}

write_aliases() {
    local category_name="$1"
    shift
    local aliases=("$@")
    
    echo "" >> "$BASH_ALIASES"
    echo "# ============================================" >> "$BASH_ALIASES"
    echo "# $category_name" >> "$BASH_ALIASES"
    echo "# Added by Dev-Control on $(date +%Y-%m-%d)" >> "$BASH_ALIASES"
    echo "# ============================================" >> "$BASH_ALIASES"
    
    for alias_line in "${aliases[@]}"; do
        echo "$alias_line" >> "$BASH_ALIASES"
    done
}

install_aliases() {
    local selections="$1"
    local installed=()
    
    # Backup existing files
    create_backup "$BASH_ALIASES"

    # Create shell-appropriate header
    if [[ "$SHELL_TYPE" == "fish" ]]; then
        mkdir -p "$(dirname "$BASH_ALIASES")"
        {
            echo "# ============================================================================"
            echo "# FISH ALIASES - Generated by Dev-Control"
            echo "# ============================================================================"
            echo "# To regenerate: dc-aliases"
            echo "# Generated on: $(date +"%Y-%m-%d %H:%M:%S")"
            echo "# Dev-Control location: $DEV_CONTROL_DIR"
            echo "# ============================================================================"
        } > "$BASH_ALIASES"
    else
        cat > "$BASH_ALIASES" << 'ALIASES_EOF'
# ============================================================================
# BASH ALIASES - Generated by Dev-Control
# ============================================================================
# 
# This file is sourced from .bashrc
# To regenerate, run: dc-aliases (or the alias-loading.sh script)
# 
# Generated on: 
ALIASES_EOF
        echo "# $(date +"%Y-%m-%d %H:%M:%S")" >> "$BASH_ALIASES"
        echo "#" >> "$BASH_ALIASES"
        echo "# Dev-Control location: $DEV_CONTROL_DIR" >> "$BASH_ALIASES"
        echo "# ============================================================================" >> "$BASH_ALIASES"
    fi

    if [[ "$selections" =~ [Aa] ]]; then
        selections="1,2,3,4,5,6,7,8,9,10"
    fi
    
    IFS=',' read -ra SELECTED <<< "$selections"
    
    for sel in "${SELECTED[@]}"; do
        sel=$(echo "$sel" | tr -d ' ')
        case $sel in
            1) if [[ "$SHELL_TYPE" == "fish" ]]; then write_aliases "DEV-CONTROL COMMANDS" "${DC_ALIASES_FISH[@]}"; else write_aliases "DEV-CONTROL COMMANDS" "${DC_ALIASES[@]}"; fi; installed+=("Dev-Control Commands") ;;
            2) if [[ "$SHELL_TYPE" == "fish" ]]; then write_aliases "GIT SHORTCUTS" "${GIT_ALIASES_FISH[@]}"; else write_aliases "GIT SHORTCUTS" "${GIT_ALIASES[@]}"; fi; installed+=("Git Shortcuts") ;;
            3) write_aliases "SAFETY NETS" "${SAFE_ALIASES[@]}"; installed+=("Safety Nets") ;;
            4) write_aliases "SYSTEM MONITORING" "${SYSMON_ALIASES[@]}"; installed+=("System Monitoring") ;;
            5) write_aliases "DIRECTORY OPERATIONS" "${DIR_ALIASES[@]}"; installed+=("Directory Operations") ;;
            6) write_aliases "NETWORK UTILITIES" "${NET_ALIASES[@]}"; installed+=("Network Utilities") ;;
            7) write_aliases "CONTAINER SHORTCUTS" "${CONTAINER_ALIASES[@]}"; installed+=("Container Shortcuts") ;;
            8) if [[ "$SHELL_TYPE" == "fish" ]]; then write_aliases "QUICK EDITS" "${EDIT_ALIASES_FISH[@]}"; else write_aliases "QUICK EDITS" "${EDIT_ALIASES[@]}"; fi; installed+=("Quick Edits") ;;
            9) write_aliases "ARCHIVE/COMPRESSION" "${ARCHIVE_ALIASES[@]}"; installed+=("Archive/Compression") ;;
            10) write_aliases "SEARCH UTILITIES" "${SEARCH_ALIASES[@]}"; installed+=("Search Utilities") ;;
        esac
    done
    
    echo "" >> "$BASH_ALIASES"
    echo "# vim: ft=${SHELL_TYPE}" >> "$BASH_ALIASES"
    
    return 0
}

setup_rc_file() {
    # Fish auto-sources ~/.config/fish/conf.d/ — no RC modification needed
    if [[ "$SHELL_TYPE" == "fish" ]]; then
        mkdir -p "$(dirname "$BASH_ALIASES")"
        print_info "Fish: aliases auto-loaded from conf.d/ (no RC modification needed)"
        BASHRC_MODIFIED="false"
        return 0
    fi

    local aliases_name
    aliases_name=$(basename "$BASH_ALIASES")
    if grep -qE "(source|\.).*${aliases_name}" "$BASHRC" 2>/dev/null; then
        print_info "$BASHRC already configured to load $aliases_name"
        BASHRC_MODIFIED="false"
        return 0
    fi

    create_backup "$BASHRC"
    local line_number
    line_number=$(wc -l < "$BASHRC")
    line_number=$((line_number + 1))

    {
        printf '\n# ============================================================================\n'
        printf '# Load custom aliases (added by Dev-Control)\n'
        printf '# ============================================================================\n'
        printf 'if [ -f ~/%s ]; then\n    . ~/%s\nfi\n' "$aliases_name" "$aliases_name"
    } >> "$BASHRC"

    BASHRC_MODIFIED="true"
    print_success "Modified $BASHRC to load $aliases_name"
    print_warning "UNDO: To revert, edit $BASHRC and remove lines $line_number onwards"
}

show_summary() {
    print_header_success "Installation Complete!"
    
    print_section "Files modified:"
    print_detail "$BASH_ALIASES" "Updated with selected aliases"
    if [[ "$BASHRC_MODIFIED" == "true" ]]; then
        print_detail "$BASHRC" "Modified to source $(basename "$BASH_ALIASES")"
    elif [[ "$SHELL_TYPE" == "fish" ]]; then
        print_detail "Fish conf.d/" "Auto-loaded (no RC modification needed)"
    else
        print_detail "$BASHRC" "Already configured (no changes)"
    fi
    
    print_section "Backup location:"
    print_list_item "$BACKUP_DIR/"
    
    print_section "To apply changes now:"
    case "$SHELL_TYPE" in
        fish)
            print_command_hint "Reload fish" "exec fish"
            print_command_hint "Or source directly" "source $BASH_ALIASES"
            ;;
        zsh)
            print_command_hint "Reload config" "source ~/.zshrc"
            print_command_hint "Or use alias" "reload"
            ;;
        *)
            print_command_hint "Reload config" "source ~/.bashrc"
            print_command_hint "Or use alias" "reload"
            ;;
    esac
    echo ""
    echo -e "${DIM}Or simply open a new terminal.${NC}"
    
    print_section "To reinstall or modify aliases later:"
    print_command_hint "Using alias" "dc-aliases"
    print_command_hint "Direct path" "$SCRIPT_DIR/alias-loading.sh"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header "Dev-Control Alias Installer"
    
    print_kv "Script directory" "$SCRIPT_DIR"
    print_kv "Dev-Control directory" "$DEV_CONTROL_DIR"
    echo ""
    
    display_menu
    
    local selection
    selection=$(get_selection)
    
    if [[ "$selection" =~ ^[Qq]$ ]]; then
        print_info "Installation cancelled. No changes made."
        exit 0
    fi
    
    if [[ -z "$selection" ]]; then
        print_error "No selection made. Exiting."
        exit 1
    fi
    
    local valid_selection=false
    if [[ "$selection" =~ [Aa] ]]; then
        valid_selection=true
    else
        IFS=',' read -ra CHECK <<< "$selection"
        for item in "${CHECK[@]}"; do
            item=$(echo "$item" | tr -d ' ')
            if [[ "$item" =~ ^[1-9]$|^10$ ]]; then
                valid_selection=true
                break
            fi
        done
    fi
    
    if [[ "$valid_selection" != "true" ]]; then
        print_error "Invalid selection: $selection"
        print_info "Use numbers 1-10, 'A' for all, or 'Q' to quit."
        exit 1
    fi
    
    echo ""
    print_step "Installing selected aliases..."
    
    install_aliases "$selection"
    setup_rc_file
    show_summary
}

main "$@"
