# ============================================================================
# DEV-TOOLS: GCC, build-essential, common compilers
# ============================================================================
#
# Category-specific layer appended after common-tools.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

RUN apt-get update && apt-get install -y \
    clang llvm gdb valgrind \
    cmake ninja-build meson \
    pkg-config autoconf automake libtool \
    && rm -rf /var/lib/apt/lists/*
