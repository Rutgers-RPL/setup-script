#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "===================================================="
echo " Starting Setup for RPL STM32 CMake Build"
echo "===================================================="

# 1. Enable the Universe repository (where arm-none-eabi lives)
echo "--> Enabling Ubuntu Universe repository..."
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe

# 2. Update package lists
echo "--> Updating package lists..."
sudo apt-get update -y

# 3. Install core build tools and language servers
echo "--> Installing build tools (Build-Essential, CMake, Ninja, Git, Clangd)..."
sudo apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    git \
    clangd

# 4. Install the ARM GCC Cross-Compiler toolchain
echo "--> Installing ARM Cross-Compiler (arm-none-eabi-gcc)..."
sudo apt-get install -y \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi \
    gdb-arm-none-eabi \
    libnewlib-arm-none-eabi

# 5. Install hardware flashing and debugging utilities
echo "--> Installing hardware utilities (OpenOCD, STLink Tools)..."
sudo apt-get install -y \
    openocd \
    stlink-tools

# 6. Verification
echo "===================================================="
echo " Verification"
echo "===================================================="
echo -n "CMake version:       " && cmake --version | head -n 1
echo -n "Ninja version:       " && ninja --version
echo -n "ARM GCC version:     " && arm-none-eabi-gcc --version | head -n 1
echo -n "Clangd version:      " && clangd --version
echo -n "OpenOCD version:     " && openocd --version | head -n 1
echo -n "ST-Link CLI version: " && st-info --version

echo "===================================================="
echo " Setup Complete! You are ready to build and flash."
echo "===================================================="