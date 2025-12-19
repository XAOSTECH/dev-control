#!/usr/bin/env bash
#
# Git-Control Alias Loading Script
# Interactive alias installer with dynamic path resolution
# 
# This script creates a .bash_aliases file and modifies .bashrc to source it.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
BASHRC="$HOME/.bashrc"
BASH_ALIASES="$HOME/.bash_aliases"
BACKUP_DIR="$HOME/.bash_backups"
BASHRC_MODIFIED="false"

# ============================================================================
# ALIAS ARRAYS - Complete alias definitions by category
# ============================================================================

# Git-Control specific shortcuts
declare -a GC_ALIASES=(
    "# Git-Control shortcuts"
    "alias gc-control='${SCRIPT_DIR}/git-control.sh'"
    "alias gc-init='${SCRIPT_DIR}/template-loading.sh'"
    "alias gc-create='${SCRIPT_DIR}/create-repo.sh'"
    "alias gc-pr='${SCRIPT_DIR}/create-pr.sh'"
    "alias gc-mcp='${SCRIPT_DIR}/mcp-setup.sh'"
    "alias gc-modules='${SCRIPT_DIR}/module-nesting.sh'"
    "alias gc-fix='${SCRIPT_DIR}/fix-history.sh'"
    "alias gc-alias='${SCRIPT_DIR}/alias-loading.sh'"
    "alias gca-alias='${SCRIPT_DIR}/alias-loading.sh <<< A && source ~/.bashrc && echo \"Changes applied (source ~/.bashrc already done)!\"'"
    "alias gc-help='echo \"gc-control: Main menu for all git-control tools\"; echo \"gc-init: Initialise repo with templates\"; echo \"gc-create: Create GitHub repo from current folder\"; echo \"gc-pr: Create pull request from current branch\"; echo \"gc-modules: Manage git submodules\"; echo \"gc-fix: Fix commit history interactively\"; echo \"gc-aliases: Reload alias installer\"'"
)

# Git shortcuts
declare -a GIT_ALIASES=(
    "# Git shortcuts"
    "alias gs='git status'"
    "alias ga='git add'"
    "alias gaa='git add .'"
    "alias gc='git commit -m'"
    "alias gca='git add . && git commit --amend --no-edit && git push --force-with-lease origin HEAD'"
    "alias gp='git push'"
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
    "alias gst='git stash'"
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

# System monitoring aliases
declare -a SYSMON_ALIASES=(
    "# System monitoring"
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
    "alias myip='curl -s ifconfig.me && echo'"
    "alias myip6='curl -s ifconfig.me/ip6 && echo'"
    "alias localip='hostname -I | awk \"{print \\$1}\"'"
    "alias ping='ping -c 5'"
    "alias fastping='ping -c 100 -i 0.2'"
    "alias ports='netstat -tulanp 2>/dev/null || ss -tulanp'"
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
    "alias dc='docker-compose'"
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

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}                 ${CYAN}Git-Control Alias Installer${NC}                ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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
    echo -e "${BOLD}Select alias categories to install:${NC}\n"
    echo -e "  ${CYAN}1)${NC} Git-Control Commands  - gc-init, gc-modules, gc-aliases"
    echo -e "  ${CYAN}2)${NC} Git Shortcuts         - gs, ga, gc, gp, gl, gco, gb..."
    echo -e "  ${CYAN}3)${NC} Safety Nets           - rm -i, cp -i, mv -i..."
    echo -e "  ${CYAN}4)${NC} System Monitoring     - ports, meminfo, disk, psg..."
    echo -e "  ${CYAN}5)${NC} Directory Operations  - md, rd, ll, la, .., ......"
    echo -e "  ${CYAN}6)${NC} Network Utilities     - myip, ping, listening..."
    echo -e "  ${CYAN}7)${NC} Container Shortcuts   - dps, di, drm, dc, dcu..."
    echo -e "  ${CYAN}8)${NC} Quick Edits           - bashrc, reload, path, now..."
    echo -e "  ${CYAN}9)${NC} Archive/Compression   - untar, mktar, zip..."
    echo -e "  ${CYAN}10)${NC} Search Utilities     - ff, fd, grep..."
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
    echo "# Added by git-control on $(date +%Y-%m-%d)" >> "$BASH_ALIASES"
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
    
    # Create new aliases file with header
    cat > "$BASH_ALIASES" << 'EOF'
# ============================================================================
# BASH ALIASES - Generated by git-control
# ============================================================================
# 
# This file is sourced from .bashrc
# To regenerate, run: gc-aliases (or the alias-loading.sh script)
# 
# Generated on: 
EOF
    echo "# $(date +"%Y-%m-%d %H:%M:%S")" >> "$BASH_ALIASES"
    echo "#" >> "$BASH_ALIASES"
    echo "# git-control location: $GIT_CONTROL_DIR" >> "$BASH_ALIASES"
    echo "# ============================================================================" >> "$BASH_ALIASES"

    if [[ "$selections" =~ [Aa] ]]; then
        selections="1,2,3,4,5,6,7,8,9,10"
    fi
    
    IFS=',' read -ra SELECTED <<< "$selections"
    
    for sel in "${SELECTED[@]}"; do
        sel=$(echo "$sel" | tr -d ' ')
        case $sel in
            1)
                write_aliases "GIT-CONTROL COMMANDS" "${GC_ALIASES[@]}"
                installed+=("Git-Control Commands")
                ;;
            2)
                write_aliases "GIT SHORTCUTS" "${GIT_ALIASES[@]}"
                installed+=("Git Shortcuts")
                ;;
            3)
                write_aliases "SAFETY NETS" "${SAFE_ALIASES[@]}"
                installed+=("Safety Nets")
                ;;
            4)
                write_aliases "SYSTEM MONITORING" "${SYSMON_ALIASES[@]}"
                installed+=("System Monitoring")
                ;;
            5)
                write_aliases "DIRECTORY OPERATIONS" "${DIR_ALIASES[@]}"
                installed+=("Directory Operations")
                ;;
            6)
                write_aliases "NETWORK UTILITIES" "${NET_ALIASES[@]}"
                installed+=("Network Utilities")
                ;;
            7)
                write_aliases "CONTAINER SHORTCUTS" "${CONTAINER_ALIASES[@]}"
                installed+=("Container Shortcuts")
                ;;
            8)
                write_aliases "QUICK EDITS" "${EDIT_ALIASES[@]}"
                installed+=("Quick Edits")
                ;;
            9)
                write_aliases "ARCHIVE/COMPRESSION" "${ARCHIVE_ALIASES[@]}"
                installed+=("Archive/Compression")
                ;;
            10)
                write_aliases "SEARCH UTILITIES" "${SEARCH_ALIASES[@]}"
                installed+=("Search Utilities")
                ;;
        esac
    done
    
    echo ""
    echo "# vim: ft=bash" >> "$BASH_ALIASES"
    
    return 0
}

setup_bashrc() {
    # Check if .bashrc already sources .bash_aliases
    if grep -q "source.*\.bash_aliases\|\..*\.bash_aliases" "$BASHRC" 2>/dev/null; then
        print_info ".bashrc already configured to load .bash_aliases"
        BASHRC_MODIFIED="false"
        return 0
    fi
    
    create_backup "$BASHRC"
    
    # Add sourcing line to .bashrc
    local line_number=$(wc -l < "$BASHRC")
    line_number=$((line_number + 1))
    
    cat >> "$BASHRC" << 'EOF'

# ============================================================================
# Load custom aliases (added by git-control)
# ============================================================================
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
EOF
    
    BASHRC_MODIFIED="true"
    print_success "Modified ~/.bashrc to load ~/.bash_aliases"
    echo -e "${YELLOW}[UNDO]${NC} To revert, edit ~/.bashrc and remove lines $line_number onwards"
    echo -e "${YELLOW}[UNDO]${NC} Run: ${CYAN}nano ~/.bashrc${NC}"
}

show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}                    ${CYAN}Installation Complete!${NC}                    ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Files modified:${NC}"
    echo -e "  • ${CYAN}~/.bash_aliases${NC} - Updated with selected aliases"
    if [[ "$BASHRC_MODIFIED" == "true" ]]; then
        echo -e "  • ${CYAN}~/.bashrc${NC} - Modified to source .bash_aliases"
    else
        echo -e "  • ${CYAN}~/.bashrc${NC} - Already configured (no changes)"
    fi
    echo ""
    echo -e "${BOLD}Backup location:${NC}"
    echo -e "  • ${CYAN}$BACKUP_DIR/${NC}"
    echo ""
    echo -e "${BOLD}To apply changes now, run:${NC}"
    echo -e "  ${GREEN}source ~/.bashrc${NC}  or  ${GREEN}reload${NC}  (after first install)"
    echo ""
    echo -e "${BOLD}Or simply open a new terminal.${NC}"
    echo ""
    echo -e "${BOLD}To reinstall or modify aliases later:${NC}"
    echo -e "  ${GREEN}gc-aliases${NC}  (if git-control aliases installed)"
    echo -e "  ${GREEN}$SCRIPT_DIR/alias-loading.sh${NC}"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header
    
    print_info "Script directory: $SCRIPT_DIR"
    print_info "Git-Control directory: $GIT_CONTROL_DIR"
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
    print_info "Installing selected aliases..."
    
    install_aliases "$selection"
    setup_bashrc
    show_summary
}

main "$@"