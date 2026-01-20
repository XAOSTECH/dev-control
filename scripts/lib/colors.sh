#!/usr/bin/env bash
#
# Git-Control Shared Library: Colors
# Common color definitions for terminal output
#
# Usage:
#   source "${SCRIPT_DIR}/lib/colors.sh"
#

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'

# Text styles
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'

# Reset
NC='\033[0m'  # No Color / Reset
RESET='\033[0m'

# Background colors
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'

# High intensity colors
HI_RED='\033[0;91m'
HI_GREEN='\033[0;92m'
HI_YELLOW='\033[0;93m'
HI_BLUE='\033[0;94m'
HI_MAGENTA='\033[0;95m'
HI_CYAN='\033[0;96m'
HI_WHITE='\033[0;97m'
